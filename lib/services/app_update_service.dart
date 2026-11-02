import '../core/ml/voice_detection_service.dart';
import '../core/ml/sms_detection_service.dart';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateService {
  static Future<Map<String, dynamic>>? _pendingCheck;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Must match the key used by SmsDetectionService.

  // Current bundled/default voice model.
  // V6 is the built-in-only re-export of the V4 weights.
  static const int defaultVoiceModelVersion = 6;

  /// Gets the latest update information from Firestore.
  Future<Map<String, dynamic>?> getLatestUpdate() async {
    log('🔄 Checking Firestore for app update information...');

    try {
      final doc = await _firestore
          .collection('app_updates')
          .doc('latest')
          .get();

      log('📡 Firestore request completed.');
      log('📄 Document exists: ${doc.exists}');

      if (!doc.exists) {
        log('⚠️ app_updates/latest does not exist.');
        return null;
      }

      final data = doc.data();

      if (data == null) {
        log('⚠️ Firestore update document contains no data.');
        return null;
      }

      log('✅ Firestore update data received: $data');

      return data;
    } catch (e, stackTrace) {
      log('❌ Failed to get app update information: $e');
      log('❌ Stack trace: $stackTrace');
      return null;
    }
  }

  /// Compares the installed PARE application and model versions
  /// against the latest versions stored in Firestore.
  Future<Map<String, dynamic>> checkForUpdates() => _pendingCheck ??=
      _checkForUpdates().whenComplete(() => _pendingCheck = null);

  Future<Map<String, dynamic>> _checkForUpdates() async {
    log('🔍 Comparing installed versions with latest versions...');

    try {
      // ------------------------------------------------------------
      // 1. Get installed application information
      // ------------------------------------------------------------
      final packageInfo = await PackageInfo.fromPlatform();

      final installedAppVersion = packageInfo.version;
      final installedAppVersionCode =
          int.tryParse(packageInfo.buildNumber) ?? 0;

      log(
        '📱 Installed App: '
        '$installedAppVersion+$installedAppVersionCode',
      );

      // ------------------------------------------------------------
      // 2. Get installed SMS model version
      // ------------------------------------------------------------
      //
      // SmsDetectionService saves the installed SMS model version
      // in SharedPreferences after a successful model update.
      //
      // If no downloaded model has ever been installed, the default
      // bundled SMS model is Version 1.
      // ------------------------------------------------------------

      final smsService = SmsDetectionService();
      final installedSmsModelVersion = await smsService
          .getInstalledModelVersion();
      smsService.close();

      log(
        '📩 Installed SMS Model Version: '
        '$installedSmsModelVersion',
      );

      // ------------------------------------------------------------
      // 3. Get installed voice model version
      // ------------------------------------------------------------
      //
      // VoiceDetectionService saves the installed voice model version
      // in SharedPreferences after a successful model update.
      //
      // If no downloaded voice model has ever been installed, the
      // bundled/default voice model is Version 6.
      // ------------------------------------------------------------
      final voiceService = VoiceDetectionService();
      final installedVoiceModelVersion = await voiceService
          .getInstalledModelVersion();
      voiceService.close();

      // ------------------------------------------------------------
      // 4. Get latest update information from Firestore
      // ------------------------------------------------------------
      final latestData = await getLatestUpdate();

      if (latestData == null) {
        return {
          'success': false,
          'appUpdateAvailable': false,
          'smsModelUpdateAvailable': false,
          'voiceModelUpdateAvailable': false,
          'anyUpdateAvailable': false,
          'installedAppVersion': installedAppVersion,
          'installedAppVersionCode': installedAppVersionCode,
          'installedSmsModelVersion': installedSmsModelVersion,
          'installedVoiceModelVersion': installedVoiceModelVersion,
          'error': 'Unable to retrieve update information.',
        };
      }

      // ------------------------------------------------------------
      // 5. Read latest versions from Firestore
      // ------------------------------------------------------------
      final latestAppVersion =
          latestData['appVersion']?.toString() ?? installedAppVersion;

      final latestAppVersionCode = _toInt(latestData['appVersionCode']);

      final latestSmsModelVersion = _toInt(latestData['smsModelVersion']);

      final latestVoiceModelVersion = _toInt(latestData['voiceModelVersion']);

      // ------------------------------------------------------------
      // 6. Compare installed versions with latest versions
      // ------------------------------------------------------------
      final appUpdateAvailable = latestAppVersionCode > installedAppVersionCode;

      final smsModelUpdateAvailable =
          latestSmsModelVersion > installedSmsModelVersion;

      final voiceModelUpdateAvailable =
          latestVoiceModelVersion > installedVoiceModelVersion;

      // ------------------------------------------------------------
      // 7. Log comparison results
      // ------------------------------------------------------------
      log('────────────────────────────────────');
      log('📱 INSTALLED APP');
      log('   Version: $installedAppVersion');
      log('   Code: $installedAppVersionCode');
      log('');

      log('☁️ LATEST APP');
      log('   Version: $latestAppVersion');
      log('   Code: $latestAppVersionCode');
      log('');

      log('📩 SMS MODEL');
      log('   Installed: $installedSmsModelVersion');
      log('   Latest: $latestSmsModelVersion');
      log('   Update available: $smsModelUpdateAvailable');
      log('');

      log('🎤 VOICE MODEL');
      log('   Installed: $installedVoiceModelVersion');
      log('   Latest: $latestVoiceModelVersion');
      log('   Update available: $voiceModelUpdateAvailable');
      log('');

      log('📦 APP UPDATE AVAILABLE: $appUpdateAvailable');
      log(
        '🔔 ANY UPDATE AVAILABLE: '
        '${appUpdateAvailable || smsModelUpdateAvailable || voiceModelUpdateAvailable}',
      );
      log('────────────────────────────────────');

      // ------------------------------------------------------------
      // 8. Return update information
      // ------------------------------------------------------------
      return {
        'success': true,

        // Installed app
        'installedAppVersion': installedAppVersion,
        'installedAppVersionCode': installedAppVersionCode,

        // Latest app
        'latestAppVersion': latestAppVersion,
        'latestAppVersionCode': latestAppVersionCode,

        // SMS model
        'installedSmsModelVersion': installedSmsModelVersion,
        'latestSmsModelVersion': latestSmsModelVersion,
        'smsModelUpdateAvailable': smsModelUpdateAvailable,

        // Voice model
        'installedVoiceModelVersion': installedVoiceModelVersion,
        'latestVoiceModelVersion': latestVoiceModelVersion,
        'voiceModelUpdateAvailable': voiceModelUpdateAvailable,

        // Application update
        'appUpdateAvailable': appUpdateAvailable,

        // Any available update
        'anyUpdateAvailable':
            appUpdateAvailable ||
            smsModelUpdateAvailable ||
            voiceModelUpdateAvailable,
      };
    } catch (e, stackTrace) {
      log('❌ Version comparison failed: $e');
      log('❌ Stack trace: $stackTrace');

      return {
        'success': false,
        'appUpdateAvailable': false,
        'smsModelUpdateAvailable': false,
        'voiceModelUpdateAvailable': false,
        'anyUpdateAvailable': false,
        'error': e.toString(),
      };
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
