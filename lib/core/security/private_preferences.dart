import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_crypto_service.dart';

/// Only operational toggles remain in preferences. Profile identifiers are
/// migrated to platform-protected storage before the UI reads them.
class PrivatePreferences {
  PrivatePreferences._(this._prefs);
  final SharedPreferences _prefs;
  static const _secure = FlutterSecureStorage();
  static const _privateKeys = {'phone', 'username', 'pending_login_phone'};
  final Map<String, String> _values = {};
  static Future<PrivatePreferences>? _instance;
  static Future<PrivatePreferences> getInstance() =>
      _instance ??= _load().catchError((Object error) {
        _instance = null;
        throw error;
      });
  static Future<PrivatePreferences> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final result = PrivatePreferences._(prefs);
    for (final key in _privateKeys) {
      var value = await _secure.read(key: 'profile_$key');
      final legacy = prefs.getString(key);
      if (value == null && legacy != null) {
        value = legacy;
        await _secure.write(key: 'profile_$key', value: value);
      }
      if (value != null) {
        result._values[key] = value;
      }
      await prefs.remove(key);
    }
    final phone = result.getString('phone');
    if (phone != null) {
      await prefs.setString(
        'sms_owner',
        await LocalCryptoService.instance.lookupKey('account:$phone'),
      );
    }
    return result;
  }

  String? getString(String key) =>
      _privateKeys.contains(key) ? _values[key] : _prefs.getString(key);
  bool? getBool(String key) => _prefs.getBool(key);
  int? getInt(String key) => _prefs.getInt(key);

  /// Background engines must observe logout and setting changes in the UI.
  Future<void> reload() async {
    await _prefs.reload();
    for (final key in _privateKeys) {
      final value = await _secure.read(key: 'profile_$key');
      if (value == null) {
        _values.remove(key);
      } else {
        _values[key] = value;
      }
    }
  }

  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);
  Future<bool> setString(String key, String value) async {
    if (!_privateKeys.contains(key)) return _prefs.setString(key, value);
    await _secure.write(key: 'profile_$key', value: value);
    _values[key] = value;
    await _prefs.remove(key);
    if (key == 'phone') {
      await _prefs.setString(
        'sms_owner',
        await LocalCryptoService.instance.lookupKey('account:$value'),
      );
    }
    return true;
  }

  Future<bool> remove(String key) async {
    if (_privateKeys.contains(key)) {
      await _secure.delete(key: 'profile_$key');
      _values.remove(key);
    }
    if (key == 'phone') await _prefs.remove('sms_owner');
    return _prefs.remove(key);
  }
}
