import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestAllProtectionPermissions() async {
    final statuses = await [
      Permission.sms,
      Permission.phone,
      Permission.microphone,
      Permission.contacts,
    ].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;
    final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
    final contactsGranted = statuses[Permission.contacts]?.isGranted ?? false;

    return smsGranted && phoneGranted && micGranted && contactsGranted;
  }

  Future<bool> requestSmsPermissions() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<bool> requestCallPermissions() async {
    final status = await Permission.phone.request();
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
}
