import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();

  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('pare_app.db');

    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // ============================================================
  // CREATE DATABASE
  // ============================================================

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firebase_uid TEXT,
        username TEXT NOT NULL,
        phone_number TEXT NOT NULL UNIQUE,
        mpin_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_login_at TEXT,
        failed_mpin_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT
      )
    ''');
  }

  // ============================================================
  // DATABASE MIGRATION
  // ============================================================

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // ==========================================================
    // Version 1 → Version 2
    // ==========================================================
    //
    // Adds Firebase UID so the local user can be associated
    // with the Firebase Authentication account.
    //

    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE users
        ADD COLUMN firebase_uid TEXT
      ''');
    }

    // ==========================================================
    // Version 2 → Version 3
    // ==========================================================
    //
    // Reserved for previous database changes.
    //

    if (oldVersion < 3) {
      // No additional changes required.
    }

    // ==========================================================
    // Version 3 → Version 4
    // ==========================================================
    //
    // Adds local authentication security information.
    //

    if (oldVersion < 4) {
      await db.execute('''
        ALTER TABLE users
        ADD COLUMN last_login_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE users
        ADD COLUMN failed_mpin_attempts INTEGER NOT NULL DEFAULT 0
      ''');

      await db.execute('''
        ALTER TABLE users
        ADD COLUMN locked_until TEXT
      ''');
    }
  }
}
