import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../core/ml/sms_detection_service.dart';
import 'notification_service.dart';
import 'sms_processing_service.dart';

/// No UI and no OTP prompt: only the already verified device's enabled SMS
/// protection runs here. This engine does not record microphone audio.
@pragma('vm:entry-point')
Future<void> runBackgroundSms() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pare_app/sms_background');
  final model = SmsDetectionService();
  var retry = false;
  try {
    await NotificationService.init();
    final processor = SmsProcessingService(model);
    final events = await channel.invokeListMethod<dynamic>('pending') ?? [];
    for (final raw in events) {
      final event = Map<String, dynamic>.from(raw as Map);
      try {
        if (await processor.process(event)) {
          await channel.invokeMethod('acknowledge', {'id': event['id']});
        }
      } catch (_) {
        retry = true;
      }
    }
  } catch (_) {
    retry = true;
  } finally {
    model.close();
    await channel.invokeMethod('finished', {'retry': retry});
  }
}
