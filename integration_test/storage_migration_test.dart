import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/database/local_database.dart';
import 'package:pare_app/core/security/local_crypto_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'History migration encrypts fields and enforces account boundaries',
    (tester) async {
      final filename =
          'security_history_test_${DateTime.now().microsecondsSinceEpoch}.db';
      final fullPath = path.join(await getDatabasesPath(), filename);
      final old = await openDatabase(
        fullPath,
        version: 5,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE detection_history (id INTEGER PRIMARY KEY AUTOINCREMENT, userPhone TEXT NOT NULL, name TEXT NOT NULL, senderNumber TEXT, type TEXT NOT NULL, message TEXT, result TEXT NOT NULL, confidence REAL NOT NULL, action TEXT NOT NULL, category TEXT NOT NULL, safe INTEGER NOT NULL, keywordScore INTEGER, riskLevel TEXT, dateTime TEXT NOT NULL, detectionExplanation TEXT, modelScore REAL, modelVersion INTEGER, smsDeliveryId TEXT UNIQUE)',
          );
        },
      );
      await old.insert('detection_history', {
        'userPhone': 'account-a',
        'name': 'Private Sender',
        'senderNumber': '09123456789',
        'type': 'SMS Message',
        'message': 'Private message',
        'result': 'Low risk',
        'confidence': .2,
        'action': 'Allowed',
        'category': 'Messages',
        'safe': 1,
        'riskLevel': 'LOW',
        'dateTime': '2026-10-30',
        'detectionExplanation': 'Private reason',
      });
      await old.close();
      final migrated = await DatabaseHelper.instance.openTestDatabase(filename);
      try {
        final store = DatabaseHelper.forTesting(migrated);
        final raw = (await migrated.query('detection_history')).single;
        expect(jsonEncode(raw), isNot(contains('Private Sender')));
        expect(jsonEncode(raw), isNot(contains('Private message')));
        expect(raw['encryptedPayload'], startsWith('gcm1:'));
        final own = await store.getHistory(userPhone: 'account-a');
        expect(own.single['name'], 'Private Sender');
        expect(own.single['message'], 'Private message');
        expect(await store.getHistory(userPhone: 'account-b'), isEmpty);
        await expectLater(store.getHistory(), throwsStateError);
        await expectLater(store.clearHistory(), throwsStateError);
        expect(
          await store.updateHistoryAction(
            historyId: own.single['id'],
            action: 'Changed',
            userPhone: 'account-b',
          ),
          0,
        );
        await store.clearHistory(userPhone: 'account-b');
        expect((await store.getHistory(userPhone: 'account-a')).length, 1);
        final ciphertext = raw['encryptedPayload'] as String;
        final parts = ciphertext.split(':');
        final bytes = base64Decode(parts[2]);
        bytes[0] ^= 1;
        parts[2] = base64Encode(bytes);
        await migrated.update('detection_history', {
          'encryptedPayload': parts.join(':'),
        });
        await expectLater(
          store.getHistory(userPhone: 'account-a'),
          throwsFormatException,
        );
      } finally {
        await migrated.close();
        await deleteDatabase(fullPath);
      }
    },
  );

  testWidgets('Legacy local profile is preserved without plaintext identifiers', (
    tester,
  ) async {
    final filename =
        'security_users_test_${DateTime.now().microsecondsSinceEpoch}.db';
    final fullPath = path.join(await getDatabasesPath(), filename);
    final old = await openDatabase(
      fullPath,
      version: 4,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, firebase_uid TEXT, username TEXT NOT NULL, phone_number TEXT NOT NULL UNIQUE, mpin_hash TEXT NOT NULL, created_at TEXT NOT NULL, last_login_at TEXT, failed_mpin_attempts INTEGER NOT NULL DEFAULT 0, locked_until TEXT)',
        );
      },
    );
    await old.insert('users', {
      'username': 'Private User',
      'phone_number': '09123456789',
      'mpin_hash': 'legacy-hash',
      'firebase_uid': 'private-uid',
      'created_at': '2026-10-30',
    });
    await old.close();
    final migrated = await LocalDatabase.instance.openTestDatabase(filename);
    try {
      final raw = (await migrated.query('users')).single;
      expect(jsonEncode(raw), isNot(contains('Private User')));
      expect(jsonEncode(raw), isNot(contains('09123456789')));
      expect(
        await LocalCryptoService.instance.decryptText(
          raw['username'] as String,
        ),
        'Private User',
      );
      expect(
        await LocalCryptoService.instance.decryptText(
          raw['mpin_hash'] as String,
        ),
        'legacy-hash',
      );
    } finally {
      await migrated.close();
      await deleteDatabase(fullPath);
    }
  });
}
