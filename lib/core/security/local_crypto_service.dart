import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalCryptoService {
  static final LocalCryptoService instance = LocalCryptoService._init();

  LocalCryptoService._init();

  static const _storage = FlutterSecureStorage();
  static const _keyName = 'pare_local_encryption_key';

  Encrypter? _encrypter;

  Future<Encrypter> _getEncrypter() async {
    if (_encrypter != null) return _encrypter!;

    String? keyString = await _storage.read(key: _keyName);

    if (keyString == null) {
      final key = Key.fromSecureRandom(32);
      keyString = key.base64;
      await _storage.write(key: _keyName, value: keyString);
    }

    final key = Key.fromBase64(keyString);
    _encrypter = Encrypter(AES(key));
    return _encrypter!;
  }

  Future<String> encryptText(String plainText) async {
    if (plainText.trim().isEmpty) return plainText;

    final encrypter = await _getEncrypter();
    final iv = IV.fromSecureRandom(16);
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    return '${iv.base64}:${encrypted.base64}';
  }

  Future<String> decryptText(String storedText) async {
    try {
      if (!storedText.contains(':')) return storedText;

      final parts = storedText.split(':');
      final iv = IV.fromBase64(parts[0]);
      final encrypted = Encrypted.fromBase64(parts[1]);

      final encrypter = await _getEncrypter();
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (_) {
      return storedText;
    }
  }
}
