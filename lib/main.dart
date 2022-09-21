import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart' as uuid;

import 'simple_database.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Isolate Channels',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Background Isolate Channels'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() {
    return _MyHomePageState();
  }
}

class _MyHomePageState extends State<MyHomePage> {
  SimpleDatabase? _database;
  List<String>? _entries;

  _MyHomePageState() {
    SharedPreferences.getInstance()
        .then((value) => value.setBool('isDebug', true));
    path_provider.getTemporaryDirectory().then((Directory? tempDir) async {
      final String dbPath = path.join(tempDir!.path, 'database.db');
      SimpleDatabase.open(dbPath).then((SimpleDatabase database) {
        setState(() {
          _database = database;
          _refresh();
        });
      });
    });
  }

  void _refresh({String query = ''}) {
    _database?.find(query).toList().then((entries) {
      setState(() {
        _entries = entries;
      });
    });
  }

  void _addDate() {
    final DateTime now = DateTime.now();
    final DateFormat formatter = DateFormat('EEEE MMMM d, HH:mm:ss\n${const uuid.Uuid().v4()}');
    final String formatted = formatter.format(now);
    _database!.addEntry(formatted).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          TextField(
            onChanged: (query) => _refresh(query: query),
            decoration: const InputDecoration(
                labelText: 'Search', suffixIcon: Icon(Icons.search)),
          ),
          Expanded(
            child: ListView.builder(
              itemBuilder: (context, index) {
                return ListTile(title: Text(_entries![index]));
              },
              itemCount: _entries?.length ?? 0,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDate,
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
    );
  }
}
