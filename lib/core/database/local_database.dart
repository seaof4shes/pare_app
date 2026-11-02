import 'package:flutter/foundation.dart';
import '../security/local_crypto_service.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();

  static Database? _database;
  static Future<Database>? _opening;

  final Database? _testDatabase;
  LocalDatabase._init() : _testDatabase = null;
  @visibleForTesting
  LocalDatabase.forTesting(Database database) : _testDatabase = database;
  @visibleForTesting
  Future<Database> openTestDatabase(String filename) => _initDB(filename);

  Future<Database> get database async {
    if (_testDatabase != null) return _testDatabase;
    if (_database != null) return _database!;

    _database = await (_opening ??= _initDB('pare_app.db').catchError((
      Object error,
    ) {
      _opening = null;
      throw error;
    }));

    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 5,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA secure_delete = ON');
      },
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
        username_lookup TEXT,
        phone_lookup TEXT UNIQUE,
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
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE users ADD COLUMN username_lookup TEXT');
      await db.execute('ALTER TABLE users ADD COLUMN phone_lookup TEXT');
      final crypto = LocalCryptoService.instance;
      for (final row in await db.query('users')) {
        final values = <String, dynamic>{
          'username_lookup': await crypto.lookupKey(
            'username:${row['username']}',
          ),
          'phone_lookup': await crypto.lookupKey(
            'phone:${row['phone_number']}',
          ),
        };
        for (final field in [
          'username',
          'phone_number',
          'firebase_uid',
          'mpin_hash',
        ]) {
          if (row[field] != null) {
            values[field] = await crypto.encryptText(row[field].toString());
          }
        }
        await db.update(
          'users',
          values,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await db.execute(
        'CREATE UNIQUE INDEX user_phone_lookup ON users(phone_lookup)',
      );
    }
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
