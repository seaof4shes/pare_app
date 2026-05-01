import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(settings);
    await Permission.notification.request();
  }

  static Future<void> showScamSmsNotification({
    required String sender,
    required String message,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final soundEnabled = prefs.getBool('notif_sound') ?? true;
    final vibrateEnabled = prefs.getBool('notif_vibrate') ?? true;

    final channelId =
        'scam_sms_channel_sound_${soundEnabled}_vibrate_$vibrateEnabled';

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          channelId,
          'Scam SMS Alerts',
          channelDescription: 'Notifications for detected scam SMS messages',
          importance: Importance.max,
          priority: Priority.high,
          playSound: soundEnabled,
          enableVibration: vibrateEnabled,
        );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'P.A.R.E Warning',
      'Possible scam SMS from $sender',
      details,
      payload: message,
    );
  }
}
