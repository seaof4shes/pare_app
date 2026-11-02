import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pare_app/core/security/private_preferences.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final StreamController<String> notificationTapController =
      StreamController<String>.broadcast();

  static Stream<String> get onNotificationTap =>
      notificationTapController.stream;

  // Stores notification payload when the app is launched
  // by tapping a notification.
  static String? _pendingNotificationPayload;

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
          debugPrint("🔔 Notification tapped: $payload");

          // Save it in case the navigation screen needs it.
          _pendingNotificationPayload = payload;

          // Notify listeners when the app is already running.
          notificationTapController.add(payload);
        }
      },
    );

    final launchDetails = await _notifications
        .getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;

      if (payload != null && payload.isNotEmpty) {
        debugPrint("🚀 App launched from notification: $payload");

        _pendingNotificationPayload = payload;
      }
    }
  }

  // Gets the pending notification payload and clears it.
  static String? consumePendingNotificationPayload() {
    final payload = _pendingNotificationPayload;

    _pendingNotificationPayload = null;

    return payload;
  }

  static Future<bool> showScamSmsNotification({
    required String sender,
    required String message,
    required String payload,
    required String riskLevel,
  }) async {
    final allowed = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    if (allowed == false) return false;
    final prefs = await PrivatePreferences.getInstance();

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
      visibility: NotificationVisibility.private,
    );

    final details = NotificationDetails(android: androidDetails);

    final isHighRisk = riskLevel.toUpperCase() == 'HIGH';

    final title = isHighRisk ? '⚠️ SCAM ALERT' : '⚠️ BE CAREFUL';

    final body = isHighRisk
        ? 'This message may be dangerous.\n'
              'Do NOT click links or share information.'
        : 'This message looks suspicious.\n'
              'Tap to check details.';

    await _notifications.show(
      int.tryParse(payload) ??
          (DateTime.now().millisecondsSinceEpoch % 2147483647),
      title,
      body,
      details,
      payload: payload,
    );
    return true;
  }

  static Future<void> clearForLogout() async {
    _pendingNotificationPayload = null;
    await _notifications.cancelAll();
  }

  static void dispose() {
    notificationTapController.close();
  }
}
