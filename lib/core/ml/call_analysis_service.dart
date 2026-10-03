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

    final String historyType = isDemo ? 'Voice Demo Test' : 'Voice Call';
    final String historyName = isDemo ? 'Manual Voice Test' : callerName;

    final String message = _buildCallMessage(
      result: result,
      isDemo: isDemo,
      callerNumber: callerNumber,
    );

    return _finalizeAndSave(
      result: result,
      historyType: historyType,
      historyName: historyName,
      callerNumber: callerNumber,
      message: message,
      category: 'Calls',
    );
  }

  /// NEW: analyze a WAV file the user picked from storage, instead of
  /// recording live audio. Reuses the same detection model and history
  /// pipeline as analyzeCall — analyzeCall's own behavior is unchanged.
  Future<Map<String, dynamic>?> analyzeUploadedFile(
    String filePath, {
    required String fileName,
  }) async {
    Map<String, dynamic> result;

    try {
      result = await _detectionService.analyzeAudioFile(
        filePath,
        fileName: fileName,
      );
    } catch (e) {
      result = {
        'label': 'Voice Detection Error',
        'result': -1,
        'confidence': 0.0,
        'fakeScore': 0.0,
        'safe': false,
        'action': 'Upload Logged Only',
      };
    }

    final String message = _buildUploadMessage(
      result: result,
      fileName: fileName,
    );

    return _finalizeAndSave(
      result: result,
      historyType: 'Voice Upload',
      historyName: fileName,
      callerNumber: 'Uploaded File',
      message: message,
      category: 'Calls',
    );
  }

  String _buildCallMessage({
    required Map<String, dynamic> result,
    required bool isDemo,
    required String callerNumber,
  }) {
    switch (result['result'] as int) {
      case -1:
        return isDemo
            ? 'Manual microphone voice test was recorded, but the model could not classify it.'
            : 'No usable audio captured from $callerNumber';
      case 0:
        final conf = (result['confidence'] as num).toDouble().toStringAsFixed(
          2,
        );
        return isDemo
            ? 'Manual microphone test analysed — $conf% human confidence.'
            : 'Voice analysed — $conf% human confidence ($callerNumber)';
      case 1:
        final conf = (result['confidence'] as num).toDouble().toStringAsFixed(
          2,
        );
        return isDemo
            ? 'Manual microphone test detected possible AI voice — $conf% confidence.'
            : 'Potential AI voice detected — $conf% confidence ($callerNumber)';
      default:
        return isDemo
            ? 'Manual 10-second microphone voice sample analysed.'
            : '10-second voice sample analysed from $callerNumber';
    }
  }

  String _buildUploadMessage({
    required Map<String, dynamic> result,
    required String fileName,
  }) {
    switch (result['result'] as int) {
      case -1:
        return 'Uploaded file "$fileName" was analysed, but the model could not classify it.';
      case 0:
        final conf = (result['confidence'] as num).toDouble().toStringAsFixed(
          2,
        );
        return 'Uploaded file "$fileName" analysed — $conf% human confidence.';
      case 1:
        final conf = (result['confidence'] as num).toDouble().toStringAsFixed(
          2,
        );
        return 'Uploaded file "$fileName" flagged as possible AI voice — $conf% confidence.';
      default:
        return 'Uploaded file "$fileName" analysed.';
    }
  }

  Future<Map<String, dynamic>?> _finalizeAndSave({
    required Map<String, dynamic> result,
    required String historyType,
    required String historyName,
    required String callerNumber,
    required String message,
    required String category,
  }) async {
    final bool isSafe = result['safe'] == true;

    final String action =
        result['action'] ?? (isSafe ? 'Allowed' : 'Alert Shown');

    final prefs = await SharedPreferences.getInstance();
    final currentPhone = prefs.getString('phone') ?? '';

    await DatabaseHelper.instance.insertHistory({
      'userPhone': currentPhone,
      'name': historyName,
      'senderNumber': callerNumber,
      'type': historyType,
      'message': await LocalCryptoService.instance.encryptText(message),
      'result': result['label'],
      'confidence': result['confidence'],
      'action': action,
      'category': category,
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
