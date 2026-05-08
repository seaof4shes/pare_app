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

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE detection_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userPhone TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        message TEXT,
        result TEXT NOT NULL,
        confidence REAL NOT NULL,
        action TEXT NOT NULL,
        category TEXT NOT NULL,
        safe INTEGER NOT NULL,
        keywordScore INTEGER DEFAULT 0,
        riskLevel TEXT DEFAULT 'LOW',
        dateTime TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE detection_history ADD COLUMN keywordScore INTEGER DEFAULT 0",
      );

      await db.execute(
        "ALTER TABLE detection_history ADD COLUMN riskLevel TEXT DEFAULT 'LOW'",
      );
    }

    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE detection_history ADD COLUMN userPhone TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Future<int> insertHistory(Map<String, dynamic> data) async {
    final db = await instance.database;
    return await db.insert('detection_history', data);
  }

  Future<List<Map<String, dynamic>>> getHistory({String? userPhone}) async {
    final db = await instance.database;

    if (userPhone != null && userPhone.trim().isNotEmpty) {
      return await db.query(
        'detection_history',
        where: 'userPhone = ?',
        whereArgs: [userPhone],
        orderBy: 'id DESC',
      );
    }

    return await db.query('detection_history', orderBy: 'id DESC');
  }

  Future<void> clearHistory({String? userPhone}) async {
    final db = await instance.database;

    if (userPhone != null && userPhone.trim().isNotEmpty) {
      await db.delete(
        'detection_history',
        where: 'userPhone = ?',
        whereArgs: [userPhone],
      );
      return;
    }

    await db.delete('detection_history');

    await db.rawDelete(
      "DELETE FROM sqlite_sequence WHERE name='detection_history'",
    );
  }
}
