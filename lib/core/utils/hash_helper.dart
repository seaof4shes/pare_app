import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/export.dart';

class HashHelper {
  static Future<String> _deriveAsync(String mpin, String salt) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final result = await const MethodChannel(
          'pare_app/crypto',
        ).invokeMethod<String>('deriveMpin', {'mpin': mpin, 'salt': salt});
        if (result == null) throw StateError('MPIN derivation unavailable');
        return result;
      } on MissingPluginException {
        // Portable implementation for tests or engines without the native bridge.
      }
    }
    return compute(_derive, [mpin, salt]);
  }

  static Future<String> hashMpin(String mpin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(mpin)) {
      throw const FormatException('MPIN must be six digits');
    }
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    final digest = await _deriveAsync(mpin, salt);
    return 'pbkdf2-sha256:600000:$salt:$digest';
  }

  static Future<bool> verify(String mpin, String stored) async {
    if (!RegExp(r'^\d{6}$').hasMatch(mpin)) return false;
    String actual;
    String expected;
    if (stored.startsWith('pbkdf2-sha256:')) {
      final parts = stored.split(':');
      if (parts.length != 4 || parts[1] != '600000') return false;
      try {
        actual = await _deriveAsync(mpin, parts[2]);
      } catch (_) {
        return false;
      }
      expected = parts[3];
    } else {
      // Successful legacy logins are upgraded immediately by UserService.
      actual = crypto.sha256.convert(utf8.encode(mpin)).toString();
      expected = stored;
    }
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}

String _derive(List<String> values) {
  final salt = base64Decode(values[1]);
  if (salt.length != 16) throw const FormatException('Invalid salt');
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), 600000, 32));
  return base64Encode(
    derivator.process(Uint8List.fromList(utf8.encode(values[0]))),
  );
}
