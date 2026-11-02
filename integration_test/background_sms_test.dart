import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/core/security/local_crypto_service.dart';
import 'package:pare_app/services/background_sms_worker.dart';

// The integration APK has its own Dart root library.
@pragma('vm:entry-point')
Future<void> smsBackgroundMain() => runBackgroundSms();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Wi-Fi status bridge delivers connectivity without requesting permissions',
    (tester) async {
      final status = await const EventChannel(
        'pare_app/wifi',
      ).receiveBroadcastStream().first.timeout(const Duration(seconds: 10));
      expect(status, isA<bool>());
    },
  );
  testWidgets(
    'Headless Android job classifies and encrypts SMS without a Home screen',
    (tester) async {
      const channel = MethodChannel('pare_app/block_sender');
      const phone = '+630000000042';
      final prefs = await PrivatePreferences.getInstance();
      final fixtureOwner = await LocalCryptoService.instance.lookupKey(
        'account:$phone',
      );
      await channel.invokeMethod('debugSmsRemoveFixtures', {
        'owner': fixtureOwner,
      });
      final originalPhone = prefs.getString('phone');
      final originals = {
        for (final key in [
          'isLoggedIn',
          'protection_activated',
          'msg_detection',
          'msg_scam_alerts',
        ])
          key: prefs.getBool(key),
      };
      final before = await channel.invokeMapMethod<String, dynamic>(
        'debugSmsStatus',
      );
      expect(
        before?['pending'],
        0,
        reason: 'Do not mix test fixtures with real pending SMS.',
      );
      final stamp = DateTime.now().millisecondsSinceEpoch;
      try {
        await prefs.setBool('protection_activated', false);
        await prefs.setString('phone', phone);
        await prefs.setBool('isLoggedIn', true);
        await prefs.setBool('msg_detection', true);
        await prefs.setBool('msg_scam_alerts', false);
        await prefs.setBool('protection_activated', true);
        expect(await channel.invokeMethod<bool>('debugSmsBackground'), isTrue);
        await channel.invokeMethod('debugSmsEnqueue', {
          'body': 'Send your OTP to our agent.',
          'timestamp': stamp,
        });
        var done = false;
        for (var i = 0; i < 90; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          final status = await channel.invokeMapMethod<String, dynamic>(
            'debugSmsStatus',
          );
          if (status?['pending'] == 0 && status?['running'] == false) {
            done = true;
            break;
          }
        }
        expect(
          done,
          isTrue,
          reason:
              'Android must run the headless worker and acknowledge the saved message.',
        );
        final records = await DatabaseHelper.instance.getHistory(
          userPhone: phone,
        );
        final record = records.single;
        expect(record['riskLevel'], 'HIGH');
        expect(record['action'], 'Logged Only');
        expect(record['detectionExplanation'], isNotEmpty);
        final db = await DatabaseHelper.instance.database;
        final raw = (await db.query(
          'detection_history',
          where: 'id = ?',
          whereArgs: [record['id']],
        )).single;
        expect(raw['encryptedPayload'], startsWith('gcm1:'));
        expect(raw['message'], isNull);
        // Replaying a delivery must not duplicate history in a new engine.
        await channel.invokeMethod('debugSmsEnqueue', {
          'body': 'Send your OTP to our agent.',
          'timestamp': stamp,
        });
        for (var i = 0; i < 90; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          final status = await channel.invokeMapMethod<String, dynamic>(
            'debugSmsStatus',
          );
          if (status?['pending'] == 0 && status?['running'] == false) break;
        }
        expect(
          (await DatabaseHelper.instance.getHistory(userPhone: phone)).length,
          1,
        );
      } finally {
        await prefs.setBool('protection_activated', false);
        await channel.invokeMethod('debugSmsRemoveFixtures', {
          'owner': fixtureOwner,
        });
        // Remove only our account's fixture, preserving real history.
        await DatabaseHelper.instance.clearHistory(userPhone: phone);
        if (originalPhone == null) {
          await prefs.remove('phone');
        } else {
          await prefs.setString('phone', originalPhone);
        }
        for (final entry in originals.entries) {
          if (entry.value == null) {
            await prefs.remove(entry.key);
          } else {
            await prefs.setBool(entry.key, entry.value!);
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
