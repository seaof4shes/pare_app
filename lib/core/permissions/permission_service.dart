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

  Future<bool> requestAllProtectionPermissions() async {
    final smsGranted = await requestSmsPermissions();
    final callGranted = await requestCallPermissions();
    final micGranted = await requestMicrophonePermission();

    return smsGranted && callGranted && micGranted;
  }
}
