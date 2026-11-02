import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Authenticated encryption with a device-protected key. Legacy values are
/// decoded only during migration; damaged authenticated ciphertext fails closed.
class LocalCryptoService {
  static final instance = LocalCryptoService._();
  LocalCryptoService._();
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'pare_local_encryption_key';
  Future<Key>? _keyFuture;
  Future<Key> _key() => _keyFuture ??= _loadKey().catchError((Object error) {
    _keyFuture = null;
    throw error;
  });
  Future<Key> _loadKey() async {
    var stored = await _storage.read(key: _keyName);
    if (stored == null) {
      stored = Key.fromSecureRandom(32).base64;
      await _storage.write(key: _keyName, value: stored);
    }
    return Key.fromBase64(stored);
  }

  Future<String> encryptText(String plainText) async {
    final key = await _key();
    final iv = IV.fromSecureRandom(12);
    final encrypted = Encrypter(
      AES(key, mode: AESMode.gcm),
    ).encrypt(plainText, iv: iv);
    return 'gcm1:${iv.base64}:${encrypted.base64}';
  }

  Future<String> decryptText(String value) async {
    if (value.startsWith('gcm1:')) {
      final parts = value.split(':');
      if (parts.length != 3) {
        throw const FormatException('Damaged protected record');
      }
      try {
        return Encrypter(
          AES(await _key(), mode: AESMode.gcm),
        ).decrypt(Encrypted.fromBase64(parts[2]), iv: IV.fromBase64(parts[1]));
      } catch (_) {
        throw const FormatException(
          'Protected record could not be authenticated',
        );
      }
    }
    // Historical SMS format: exactly two base64 fields, with a 16-byte IV.
    final parts = value.split(':');
    if (parts.length == 2 &&
        RegExp(r'^[A-Za-z0-9+/]{22}==$').hasMatch(parts[0]) &&
        RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(parts[1])) {
      return Encrypter(
        AES(await _key()),
      ).decrypt(Encrypted.fromBase64(parts[1]), iv: IV.fromBase64(parts[0]));
    }
    return value;
  }

  Future<String> lookupKey(String value) async => crypto.Hmac(
    crypto.sha256,
    (await _key()).bytes,
  ).convert(utf8.encode(value)).toString();
}
