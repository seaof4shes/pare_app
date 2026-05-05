import 'package:pare_app/core/database/database_helper.dart';
import 'voice_recording_service.dart';
import 'voice_detection_service.dart';

class CallAnalysisService {
  final VoiceRecordingService _recordingService = VoiceRecordingService();
  final VoiceDetectionService _detectionService = VoiceDetectionService();

  Future<Map<String, dynamic>?> analyzeCall({
    String callerName = 'Unknown Caller',
    String callerNumber = 'Unknown Number',
  }) async {
    final wavPath = await _recordingService.recordTenSeconds();

    Map<String, dynamic> result;

    if (wavPath == null) {
      // Could be permission denied OR a truly silent recording.
      // Always save to history so the user sees the call was processed.
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

    final bool isSafe = result['safe'] == true;

    // Build a human-readable action string
    final String action =
        result['action'] ?? (isSafe ? 'Allowed' : 'Alert Shown');

    // Build a descriptive message for the history card
    final String message;
    switch (result['result'] as int) {
      case -1:
        message = 'No usable audio captured from $callerNumber';
        break;
      case 0:
        final conf = (result['confidence'] as double).toStringAsFixed(1);
        message = 'Voice analysed — $conf% human confidence ($callerNumber)';
        break;
      case 1:
        final conf = (result['confidence'] as double).toStringAsFixed(1);
        message =
            'Potential AI voice detected — $conf% confidence ($callerNumber)';
        break;
      default:
        message = '10-second voice sample analysed from $callerNumber';
    }

    await DatabaseHelper.instance.insertHistory({
      'name': callerName,
      'type': 'Voice Call',
      'message': message,
      'result': result['label'],
      'confidence': result['confidence'],
      'action': action,
      'category': 'Calls',
      'safe': isSafe ? 1 : 0,
      'dateTime': DateTime.now().toIso8601String(),
    });

    return {
      ...result,
      'callerName': callerName,
      'callerNumber': callerNumber,
      'action': action,
    };
  }

  Future<void> dispose() async {
    await _recordingService.dispose();
    _detectionService.close();
  }
}
