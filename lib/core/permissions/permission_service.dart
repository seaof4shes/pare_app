import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestSmsPermissions() async {
    final statuses = await [Permission.sms].request();
    return statuses[Permission.sms]?.isGranted ?? false;
  }

  Future<bool> requestCallPermissions() async {
    final phoneStatus = await Permission.phone.request();
    return phoneStatus.isGranted;
  }

  Future<bool> requestMicrophonePermission() async {
    final micStatus = await Permission.microphone.request();
    return micStatus.isGranted;
  }

  Future<bool> requestContactsPermission() async {
    final contactStatus = await Permission.contacts.request();
    return contactStatus.isGranted;
  }

  Future<bool> requestAllProtectionPermissions() async {
    final smsGranted = await requestSmsPermissions();
    final callGranted = await requestCallPermissions();
    final micGranted = await requestMicrophonePermission();
    final contactsGranted = await requestContactsPermission();

    return smsGranted && callGranted && micGranted && contactsGranted;
  }
}
