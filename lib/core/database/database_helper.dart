import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pare_local.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE detection_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        message TEXT,
        result TEXT NOT NULL,
        confidence REAL NOT NULL,
        action TEXT NOT NULL,
        category TEXT NOT NULL,
        safe INTEGER NOT NULL,
        dateTime TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertHistory(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('detection_history', data);
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await instance.database;
    return await db.query('detection_history', orderBy: 'id DESC');
  }

  Future<void> clearHistory() async {
    final db = await instance.database;
    await db.delete('detection_history');
  }
}
