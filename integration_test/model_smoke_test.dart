import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pare_app/core/ml/sms_detection_service.dart';
import 'package:pare_app/core/ml/voice_detection_service.dart';
import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/database/local_database.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/core/utils/hash_helper.dart';
import 'package:flutter/services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native MPIN matches existing PBKDF2 hashes and rejects wrong PIN',
    (tester) async {
      const salt = 'AAAAAAAAAAAAAAAAAAAAAA==';
      const digest = 'dzvIuzkyn1i+FIucBCG1CEItdQ5Qt0fGFN5PtVF7Tkk=';
      final timer = Stopwatch()..start();
      final native = await const MethodChannel(
        'pare_app/crypto',
      ).invokeMethod<String>('deriveMpin', {'mpin': '123456', 'salt': salt});
      timer.stop();
      expect(native, digest);
      debugPrint('Native MPIN derivation: ${timer.elapsedMilliseconds} ms');
      expect(
        await HashHelper.verify('123456', 'pbkdf2-sha256:600000:$salt:$digest'),
        isTrue,
      );
      expect(
        await HashHelper.verify('654321', 'pbkdf2-sha256:600000:$salt:$digest'),
        isFalse,
      );
    },
  );
  testWidgets('Real Android model runtime and existing history migration', (
    tester,
  ) async {
    final sms = SmsDetectionService();
    final voice = VoiceDetectionService();
    try {
      await PrivatePreferences.getInstance();
      expect(await sms.getInstalledModelVersion(), greaterThanOrEqualTo(4));
      final reminder = await sms.predict(
        'Reminder: Your appointment is scheduled for Friday at 10:00 AM. Please contact our service desk if you need to reschedule.',
      );
      expect(reminder.riskLevel, 'LOW');
      final otp = await sms.predict('Send your OTP to our agent.');
      expect(otp.riskLevel, 'HIGH');
      // Exercises the built-in-only voice runtime without TensorFlow Flex.
      await voice.loadModel();
      expect(await voice.getInstalledModelVersion(), greaterThanOrEqualTo(6));
      final temp = await getTemporaryDirectory();
      final sample = File('${temp.path}/pare_model_smoke_fixture.wav');
      try {
        await sample.writeAsBytes(_wav(silent: true));
        final silence = await voice.analyzeWavFile(sample.path);
        expect(silence['result'], -1);
        expect(silence['safe'], isFalse);
        await sample.writeAsBytes(_wav(silent: false));
        final signal = await voice.analyzeWavFile(sample.path);
        expect(signal['result'], isIn([0, 1]));
        expect((signal['fakeScore'] as num).isFinite, isTrue);
        expect(
          await sample.exists(),
          isTrue,
          reason: 'Analysis must preserve caller-owned audio.',
        );
      } finally {
        if (await sample.exists()) await sample.delete();
      }
      final db = await DatabaseHelper.instance.database;
      final columns = await db.rawQuery('PRAGMA table_info(detection_history)');
      expect(
        columns.map((c) => c['name']),
        containsAll([
          'detectionExplanation',
          'modelScore',
          'modelVersion',
          'smsDeliveryId',
        ]),
      );
      for (final row in await db.query('detection_history')) {
        expect(row['encryptedPayload'], startsWith('gcm1:'));
        expect(row['message'], isNull);
        expect(row['name'], isEmpty);
      }
      final profiles = await LocalDatabase.instance.database;
      for (final row in await profiles.query('users')) {
        for (final field in ['username', 'phone_number', 'mpin_hash']) {
          expect(row[field], startsWith('gcm1:'));
        }
      }
    } finally {
      sms.close();
      voice.close();
    }
  });
}

Uint8List _wav({required bool silent}) {
  const samples = 80000;
  final bytes = Uint8List(44 + samples * 2);
  final data = ByteData.sublistView(bytes);
  void tag(int at, String value) =>
      bytes.setRange(at, at + value.length, value.codeUnits);
  tag(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + i * 2,
      silent ? 0 : (6000 * sin(2 * pi * 220 * i / 16000)).round(),
      Endian.little,
    );
  }
  return bytes;
}
