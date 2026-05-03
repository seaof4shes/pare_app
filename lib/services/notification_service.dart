import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final StreamController<String> notificationTapController =
      StreamController<String>.broadcast();

  static Stream<String> get onNotificationTap =>
      notificationTapController.stream;

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;

        if (payload != null && payload.isNotEmpty) {
          notificationTapController.add(payload);
        }
      },
    );

    await Permission.notification.request();

    // 🔥 ADD THIS PART
    final launchDetails = await _notifications
        .getNotificationAppLaunchDetails();

    final payload = launchDetails?.notificationResponse?.payload;

    if (launchDetails?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        notificationTapController.add(payload);
      });
    }
  }

  static Future<void> showScamSmsNotification({
    required String sender,
    required String message,
    required String payload,
    required String riskLevel,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final soundEnabled = prefs.getBool('notif_sound') ?? true;
    final vibrateEnabled = prefs.getBool('notif_vibrate') ?? true;

    final channelId =
        'scam_sms_channel_sound_${soundEnabled}_vibrate_$vibrateEnabled';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      'Scam SMS Alerts',
      channelDescription: 'Notifications for detected scam SMS messages',
      importance: Importance.max,
      priority: Priority.high,
      playSound: soundEnabled,
      enableVibration: vibrateEnabled,
    );

    final details = NotificationDetails(android: androidDetails);

    final isHighRisk = riskLevel.toUpperCase() == 'HIGH';

    final title = isHighRisk ? '⚠️ SCAM ALERT' : '⚠️ BE CAREFUL';

    final body = isHighRisk
        ? 'This message may be dangerous.\nDo NOT click links or share information.'
        : 'This message looks suspicious.\nTap to check details.';

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
