import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/security/local_crypto_service.dart';

import 'voice_recording_service.dart';
import 'voice_detection_service.dart';

class CallAnalysisService {
  final VoiceRecordingService _recordingService = VoiceRecordingService();
  final VoiceDetectionService _detectionService = VoiceDetectionService();

  Future<Map<String, dynamic>?> analyzeCall({
    String callerName = 'Unknown Caller',
    String callerNumber = 'Unknown Number',
  }) async {
    final bool isDemo = callerNumber == 'Microphone Demo';

    final wavPath = await _recordingService.recordTenSeconds(demoMode: isDemo);

    Map<String, dynamic> result;

    try {
      if (wavPath == null) {
        result = {
          'label': 'No Voice Detected',
          'result': -1,
          'confidence': 0.0,
          'fakeScore': 0.0,
          'safe': true,
          'action': 'No audio captured',
        };
      } else {
        result = await _detectionService.analyzeWavFile(wavPath);
      }
    } catch (e) {
      result = {
        'label': 'Voice Detection Error',
        'result': -1,
        'confidence': 0.0,
        'fakeScore': 0.0,
        'safe': false,
        'action': isDemo ? 'Demo Logged Only' : 'Call Logged Only',
      };
    }

    final bool isSafe = result['safe'] == true;

    final String action =
        result['action'] ?? (isSafe ? 'Allowed' : 'Alert Shown');

    final String historyType = isDemo ? 'Voice Demo Test' : 'Voice Call';
    final String historyName = isDemo ? 'Manual Voice Test' : callerName;

    final String message;

    switch (result['result'] as int) {
      case -1:
        message = isDemo
            ? 'Manual microphone voice test was recorded, but the model could not classify it.'
            : 'No usable audio captured from $callerNumber';
        break;
      case 0:
        final conf = (result['confidence'] as num).toDouble().toStringAsFixed(
          2,
        );
        message = isDemo
            ? 'Manual microphone test analysed — $conf% human confidence.'
            : 'Voice analysed — $conf% human confidence ($callerNumber)';
        break;
      case 1:
        final conf = (result['confidence'] as num).toDouble().toStringAsFixed(
          2,
        );
        message = isDemo
            ? 'Manual microphone test detected possible AI voice — $conf% confidence.'
            : 'Potential AI voice detected — $conf% confidence ($callerNumber)';
        break;
      default:
        message = isDemo
            ? 'Manual 10-second microphone voice sample analysed.'
            : '10-second voice sample analysed from $callerNumber';
    }

    final prefs = await SharedPreferences.getInstance();
    final currentPhone = prefs.getString('phone') ?? '';

    await DatabaseHelper.instance.insertHistory({
      'userPhone': currentPhone,
      'name': historyName,
      'type': historyType,
      'message': await LocalCryptoService.instance.encryptText(message),
      'result': result['label'],
      'confidence': result['confidence'],
      'action': action,
      'category': 'Calls',
      'safe': isSafe ? 1 : 0,
      'keywordScore': 0,
      'riskLevel': result['label'].toString().toLowerCase().contains('deepfake')
          ? 'HIGH'
          : result['label'].toString().toLowerCase().contains('suspicious')
          ? 'MEDIUM'
          : isSafe
          ? 'LOW'
          : 'MEDIUM',
      'dateTime': DateTime.now().toIso8601String(),
    });

    return {
      ...result,
      'callerName': historyName,
      'callerNumber': callerNumber,
      'type': historyType,
      'action': action,
    };
  }

  Future<void> dispose() async {
    await _recordingService.dispose();
    _detectionService.close();
  }
}
