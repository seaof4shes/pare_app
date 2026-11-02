import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encryption;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/core/security/local_crypto_service.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/core/utils/hash_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = encryption.Key.fromSecureRandom(32);
  FlutterSecureStorage.setMockInitialValues({
    'pare_local_encryption_key': key.base64,
  });
  final crypto = LocalCryptoService.instance;
  test(
    'Authenticated ciphertext is randomized and rejects tampering',
    () async {
      final values = await Future.wait(
        List.generate(10, (_) => crypto.encryptText('Private SMS and sender')),
      );
      expect(values.toSet().length, 10);
      for (final value in values) {
        expect(await crypto.decryptText(value), 'Private SMS and sender');
      }
      final parts = values.first.split(':');
      final bytes = base64Decode(parts[2]);
      bytes[0] ^= 1;
      parts[2] = base64Encode(bytes);
      await expectLater(
        crypto.decryptText(parts.join(':')),
        throwsFormatException,
      );
    },
  );
  test(
    'Legacy encryption and ordinary text with colons remain readable',
    () async {
      final iv = encryption.IV.fromSecureRandom(16);
      final old = encryption.Encrypter(
        encryption.AES(key),
      ).encrypt('Previous history', iv: iv);
      expect(
        await crypto.decryptText('${iv.base64}:${old.base64}'),
        'Previous history',
      );
      expect(
        await crypto.decryptText('Reminder: appointment tomorrow'),
        'Reminder: appointment tomorrow',
      );
    },
  );
  test('Profile moves out of ordinary preferences without losing it', () async {
    SharedPreferences.setMockInitialValues({
      'phone': '+630000000000',
      'username': 'Test Profile',
    });
    final private = await PrivatePreferences.getInstance();
    final raw = await SharedPreferences.getInstance();
    expect(private.getString('phone'), '+630000000000');
    expect(private.getString('username'), 'Test Profile');
    expect(raw.getString('phone'), isNull);
    expect(raw.getString('username'), isNull);
    expect(raw.getString('sms_owner'), isNot(contains('+630000000000')));
    await private.remove('phone');
    expect(private.getString('phone'), isNull);
    expect(raw.getString('sms_owner'), isNull);
  });
  test(
    'MPIN has a random salt, verifies correctly and rejects a wrong PIN',
    () async {
      final first = await HashHelper.hashMpin('123456');
      final second = await HashHelper.hashMpin('123456');
      expect(first, isNot(second));
      expect(await HashHelper.verify('123456', first), isTrue);
      expect(await HashHelper.verify('654321', first), isFalse);
      await expectLater(HashHelper.hashMpin('abc123'), throwsFormatException);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
