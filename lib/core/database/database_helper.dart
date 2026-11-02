import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../security/local_crypto_service.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static Future<Database>? _opening;

  final Database? _testDatabase;
  DatabaseHelper._init() : _testDatabase = null;
  @visibleForTesting
  DatabaseHelper.forTesting(Database database) : _testDatabase = database;
  @visibleForTesting
  Future<Database> openTestDatabase(String filename) => _initDB(filename);

  Future<Database> get database async {
    if (_testDatabase != null) return _testDatabase;
    if (_database != null) return _database!;

    _database = await (_opening ??= _initDB('pare_local.db').catchError((
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
      version: 6,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA secure_delete = ON');
      },
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
        senderNumber TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL,
        message TEXT,
        result TEXT NOT NULL,
        confidence REAL NOT NULL,
        action TEXT NOT NULL,
        category TEXT NOT NULL,
        safe INTEGER NOT NULL,
        keywordScore INTEGER DEFAULT 0,
        riskLevel TEXT DEFAULT 'LOW',
        detectionExplanation TEXT,
        modelScore REAL,
        modelVersion INTEGER,
        smsDeliveryId TEXT UNIQUE,
        encryptedPayload TEXT,
        dateTime TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE detection_history ADD COLUMN detectionExplanation TEXT',
      );
      await db.execute(
        'ALTER TABLE detection_history ADD COLUMN modelScore REAL',
      );
      await db.execute(
        'ALTER TABLE detection_history ADD COLUMN modelVersion INTEGER',
      );
      await db.execute(
        'ALTER TABLE detection_history ADD COLUMN smsDeliveryId TEXT',
      );
      await db.execute(
        'CREATE UNIQUE INDEX sms_delivery_id ON detection_history(smsDeliveryId)',
      );
    }
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE detection_history "
        "ADD COLUMN keywordScore INTEGER DEFAULT 0",
      );

      await db.execute(
        "ALTER TABLE detection_history "
        "ADD COLUMN riskLevel TEXT DEFAULT 'LOW'",
      );
    }

    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE detection_history "
        "ADD COLUMN userPhone TEXT NOT NULL DEFAULT ''",
      );
    }

    // Version 4:
    // Store the actual SMS sender number separately
    // from the display/contact name.
    if (oldVersion < 4) {
      await db.execute(
        "ALTER TABLE detection_history "
        "ADD COLUMN senderNumber TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE detection_history ADD COLUMN encryptedPayload TEXT',
      );
      for (final row in await db.query('detection_history')) {
        final original = Map<String, dynamic>.from(row)
          ..remove('encryptedPayload');
        original['message'] = await LocalCryptoService.instance.decryptText(
          original['message']?.toString() ?? '',
        );
        final protected = await _protect(original);
        await db.update(
          'detection_history',
          protected,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  }

  Future<Map<String, dynamic>> _protect(Map<String, dynamic> data) async {
    final owner = data['userPhone']?.toString() ?? '';
    return {
      'userPhone':
          'h1:${await LocalCryptoService.instance.lookupKey('account:$owner')}',
      'name': '',
      'senderNumber': '',
      'type': '',
      'message': null,
      'result': '',
      'confidence': 0.0,
      'action': '',
      'category': '',
      'safe': 0,
      'keywordScore': 0,
      'riskLevel': '',
      'dateTime': '',
      'detectionExplanation': null,
      'modelScore': null,
      'modelVersion': null,
      'smsDeliveryId': data['smsDeliveryId'],
      'encryptedPayload': await LocalCryptoService.instance.encryptText(
        jsonEncode(data),
      ),
    };
  }

  Future<String> _owner(String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      throw StateError('Sign in to access history');
    }
    return 'h1:${await LocalCryptoService.instance.lookupKey('account:$phone')}';
  }

  Future<Map<String, dynamic>> _decode(
    Map<String, dynamic> row,
    String phone,
  ) async {
    final data = Map<String, dynamic>.from(
      jsonDecode(
            await LocalCryptoService.instance.decryptText(
              row['encryptedPayload'] as String,
            ),
          )
          as Map,
    );
    if (data['userPhone'] != phone) {
      throw const FormatException('History ownership mismatch');
    }
    data['id'] = row['id'];
    return data;
  }

  Future<int> insertHistory(Map<String, dynamic> data) async {
    await _owner(data['userPhone']?.toString());
    final db = await database;
    final protected = await _protect(data);
    return db.transaction((txn) async {
      if (data['smsDeliveryId'] != null) {
        final rows = await txn.query(
          'detection_history',
          columns: ['id'],
          where: 'smsDeliveryId = ?',
          whereArgs: [data['smsDeliveryId']],
          limit: 1,
        );
        if (rows.isNotEmpty) return 0;
      }
      return txn.insert('detection_history', protected);
    });
  }

  Future<List<Map<String, dynamic>>> getHistory({String? userPhone}) async {
    final owner = await _owner(userPhone);
    final db = await database;
    final rows = await db.query(
      'detection_history',
      where: 'userPhone = ?',
      whereArgs: [owner],
      orderBy: 'id DESC',
    );
    return Future.wait(rows.map((row) => _decode(row, userPhone!)));
  }

  Future<int> updateHistoryAction({
    required int historyId,
    required String action,
    String? userPhone,
  }) async {
    final owner = await _owner(userPhone);
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'detection_history',
        where: 'id = ? AND userPhone = ?',
        whereArgs: [historyId, owner],
      );
      if (rows.isEmpty) return 0;
      final data = await _decode(rows.first, userPhone!);
      data['action'] = action;
      return txn.update(
        'detection_history',
        await _protect(data),
        where: 'id = ? AND userPhone = ?',
        whereArgs: [historyId, owner],
      );
    });
  }

  Future<void> clearHistory({String? userPhone}) async {
    final owner = await _owner(userPhone);
    final db = await database;
    await db.delete(
      'detection_history',
      where: 'userPhone = ?',
      whereArgs: [owner],
    );
  }
}
