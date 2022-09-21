import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int entrySize = 256;

enum _Commands {
  init,
  add,
  query,
  ack,
  result,
  done,
}

Iterable<T> _repeat<T>(T value, int count) sync* {
  for (int i = 0; i < count; ++i) {
    yield value;
  }
}

class _SimpleDatabaseServer {
  final SendPort _sendPort;
  String? _path;
  SharedPreferences? _sharedPreferences;

  _SimpleDatabaseServer(this._sendPort);

  bool get isDebug => _sharedPreferences?.getBool('isDebug') ?? false;

  static void _run(SendPort sendPort) {
    ReceivePort receivePort = ReceivePort();
    sendPort.send([_Commands.init, receivePort.sendPort]);
    final _SimpleDatabaseServer server = _SimpleDatabaseServer(sendPort);
    receivePort.listen((dynamic message) async {
      final List command = message as List;
      server.onCommand(command);
    });
  }

  Future<void> _doAddEntry(String value) async {
    if (isDebug) {
      print('Performing add: $value');
    }
    File file = File(_path!);
    if (!file.existsSync()) {
      file.createSync();
    }
    RandomAccessFile writer = await file.open(mode: FileMode.append);
    List<int> bytes = utf8.encode(value);
    if (bytes.length > entrySize) {
      bytes = bytes.sublist(0, entrySize);
    } else if (bytes.length < entrySize) {
      List<int> newBytes = List.filled(entrySize, 0);
      for (int i = 0; i < bytes.length; ++i) {
        newBytes[i] = bytes[i];
      }
      bytes = newBytes;
    }
    await writer.writeFrom(bytes);
    await writer.close();
    _sendPort.send([_Commands.ack, null]);
  }

  Future<void> _doFind(String query) async {
    if (isDebug) {
      print('Performing find: $query');
    }
    File file = File(_path!);
    if (file.existsSync()) {
      RandomAccessFile reader = file.openSync();
      List<int> buffer = List.filled(entrySize, 0);
      while (reader.readIntoSync(buffer) == entrySize) {
        List<int> foo = buffer.takeWhile((value) => value != 0).toList();
        String string = utf8.decode(foo);
        if (string.contains(query)) {
          _sendPort.send([_Commands.result, string]);
        }
      }
      reader.closeSync();
    }
    _sendPort.send([_Commands.done, null]);
  }

  Future<void> onCommand(List command) async {
    if (command[0] == _Commands.init) {
      _path = command[1];
      BackgroundIsolateBinaryMessenger.ensureInitialized(command[2]);
      _sharedPreferences = await SharedPreferences.getInstance();
    } else if (command[0] == _Commands.add) {
      await _doAddEntry(command[1]);
    } else if (command[0] == _Commands.query) {
      _doFind(command[1]);
    }
  }
}

class SimpleDatabase {
  final Isolate _isolate;
  final String _path;
  late final SendPort _sendPort;
  final Queue<Completer<void>> _completers = Queue<Completer<void>>();
  final Queue<StreamController<String>> _resultsStream =
      Queue<StreamController<String>>();

  SimpleDatabase._(this._isolate, this._path);

  static Future<SimpleDatabase> open(String path) async {
    final ReceivePort receivePort = ReceivePort();
    final Isolate isolate =
        await Isolate.spawn(_SimpleDatabaseServer._run, receivePort.sendPort);
    final SimpleDatabase result = SimpleDatabase._(isolate, path);
    Completer<void> completer = Completer<void>();
    result._completers.addFirst(completer);
    receivePort.listen((message) {
      result._onCommand(message as List);
    });
    await completer.future;
    return result;
  }

  Future<void> addEntry(String value) {
    Completer<void> completer = Completer<void>();
    _completers.addFirst(completer);
    _sendPort.send([_Commands.add, value]);
    return completer.future;
  }

  Stream<String> find(String query) {
    StreamController<String> resultsStream = StreamController<String>();
    _resultsStream.addFirst(resultsStream);
    _sendPort.send([_Commands.query, query]);
    return resultsStream.stream;
  }

  void _onCommand(List command) {
    if (command[0] == _Commands.init) {
      _sendPort = command[1];
      _completers.removeLast().complete();
      _sendPort.send([_Commands.init, _path, RootIsolateToken.instance]);
    } else if (command[0] == _Commands.ack) {
      _completers.removeLast().complete();
    } else if (command[0] == _Commands.result) {
      _resultsStream.last.add(command[1]);
    } else if (command[0] == _Commands.done) {
      _resultsStream.removeLast().close();
    }
  }
}
