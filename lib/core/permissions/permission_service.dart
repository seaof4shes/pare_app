import '../security/private_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestAllProtectionPermissions() async {
    final prefs = await PrivatePreferences.getInstance();
    final sms = prefs.getBool('msg_detection') ?? true;
    final voice = prefs.getBool('call_detection') ?? true;
    if (!sms && !voice) return false;
    final requiredPermissions = <Permission>[
      if (sms) Permission.sms,
      if (voice) Permission.microphone,
      if (voice) Permission.phone,
    ];
    final statuses = await requiredPermissions.request();
    // Names and notifications enhance the experience but are not prerequisites
    // for locally analyzing a message. Denied alerts remain visible in settings.
    await Permission.notification.request();
    return requiredPermissions.every(
      (permission) => statuses[permission]?.isGranted ?? false,
    );
  }

  Future<bool> requestSmsPermissions() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> requestContactsPermission() async {
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }
}
