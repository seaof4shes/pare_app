import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pare_app/core/theme/pare_brand.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pare_app/core/security/private_preferences.dart';

class NotificationService {
  static Future<ByteArrayAndroidBitmap?>? _largeIcon;

  // Android small icons must be monochrome. The notification's large icon
  // uses the exact same full-color asset as the splash/launcher, scaled to
  // avoid transferring the full-resolution image through the platform channel.
  static Future<ByteArrayAndroidBitmap?> _loadLargeIcon() async {
    try {
      final bytes = await rootBundle.load(PareBrand.logoAsset);
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        targetWidth: 128,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final png = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          return png == null
              ? null
              : ByteArrayAndroidBitmap(
                  png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
                );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // A branding asset failure must never suppress a scam warning.
      return null;
    }
  }

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
        AndroidInitializationSettings('@drawable/ic_stat_pare');

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
    String? detectionSummary,
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
      icon: 'ic_stat_pare',
      largeIcon: await (_largeIcon ??= _loadLargeIcon()),
    );

    final details = NotificationDetails(android: androidDetails);

    final isHighRisk = riskLevel.toUpperCase() == 'HIGH';

    final title = isHighRisk ? '⚠️ SCAM ALERT' : '⚠️ BE CAREFUL';

    final body = detectionSummary != null && detectionSummary.trim().isNotEmpty
        ? '$detectionSummary\nTap to read the detected signs and safety advice.'
        : isHighRisk
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
