import '../core/database/database_helper.dart';
import '../core/ml/sms_detection_service.dart';
import '../core/security/private_preferences.dart';
import 'notification_service.dart';

/// Shared by the UI and Android's headless worker. A delivery ID is unique in
/// SQLite, so a replay or competing engine cannot create duplicate history.
class SmsProcessingService {
  SmsProcessingService(this.model);
  final SmsDetectionService model;

  Future<bool> process(Map<String, dynamic> event) async {
    final prefs = await PrivatePreferences.getInstance();
    await prefs.reload();
    final phone = prefs.getString('phone');
    bool permitted() =>
        phone != null &&
        phone.isNotEmpty &&
        prefs.getString('phone') == phone &&
        prefs.getBool('isLoggedIn') == true &&
        prefs.getBool('protection_activated') == true &&
        (prefs.getBool('msg_detection') ?? true) &&
        (event['owner'] == prefs.getString('sms_owner') ||
            event['owner'] == phone);
    if (!permitted()) return true;
    final message = event['body']?.toString() ?? '';
    if (message.isEmpty) return true;
    final result = await model.predict(message);
    await prefs.reload();
    if (!permitted()) return true;
    final senderNumber = event['senderNumber']?.toString() ?? 'Unknown';
    final senderName = event['senderName']?.toString() ?? '';
    final sender = senderName.isEmpty ? senderNumber : senderName;
    final risky = result.riskLevel != 'LOW';
    final received = (event['receivedAt'] as num?)?.toInt();
    final id = await DatabaseHelper.instance.insertHistory({
      'userPhone': phone,
      'name': sender,
      'senderNumber': senderNumber,
      'type': 'SMS Message',
      'message': message,
      'result': result.riskLevel == 'HIGH'
          ? 'High risk'
          : risky
          ? 'Needs review'
          : 'Low risk',
      'confidence': result.riskScore,
      'action': 'Logged Only',
      'category': 'Messages',
      'safe': risky ? 0 : 1,
      'smsDeliveryId': event['id'],
      'detectionExplanation': result.explanation,
      'modelScore': result.scamProbability,
      'modelVersion': result.modelVersion,
      'keywordScore': result.keywordScore,
      'riskLevel': result.riskLevel,
      'dateTime':
          (received == null
                  ? DateTime.now()
                  : DateTime.fromMillisecondsSinceEpoch(received))
              .toIso8601String(),
    });
    await prefs.reload();
    if (id > 0 &&
        risky &&
        permitted() &&
        (prefs.getBool('msg_scam_alerts') ?? true)) {
      final shown = await NotificationService.showScamSmsNotification(
        sender: sender,
        message: message,
        payload: id.toString(),
        riskLevel: result.riskLevel,
        detectionSummary: result.explanation.split('\n\n').first,
      );
      if (shown) {
        await DatabaseHelper.instance.updateHistoryAction(
          historyId: id,
          action: 'Alert Shown',
          userPhone: phone,
        );
      }
    }
    return true;
  }
}
