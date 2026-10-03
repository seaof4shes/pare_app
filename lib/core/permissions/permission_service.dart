import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestAllProtectionPermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.microphone,
      Permission.contacts,
      Permission.notification,
    ].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
    final contactsGranted = statuses[Permission.contacts]?.isGranted ?? false;
    final notificationGranted =
        statuses[Permission.notification]?.isGranted ?? false;

    return smsGranted && micGranted && contactsGranted && notificationGranted;
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
