import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/core/ml/sms_detection_service.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/services/sms_processing_service.dart';

class GuardModel extends SmsDetectionService {
  int calls = 0;
  Future<void> Function()? duringPrediction;
  @override
  Future<SmsDetectionResult> predict(String text) async {
    calls++;
    await duringPrediction?.call();
    return SmsDetectionResult(
      scamProbability: 0.9,
      label: 'Scam',
      riskLevel: 'HIGH',
      keywordScore: 2,
      riskScore: 0.9,
      explanation: 'Test',
      modelVersion: 4,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({'profile_phone': '+630000000042'});
  SharedPreferences.setMockInitialValues({});
  late PrivatePreferences prefs;
  late GuardModel model;
  late Map<String, dynamic> event;
  setUp(() async {
    prefs = await PrivatePreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setBool('protection_activated', true);
    await prefs.setBool('msg_detection', true);
    model = GuardModel();
    event = {
      'owner': prefs.getString('sms_owner'),
      'body': 'Send your OTP',
      'id': 'fixture',
    };
  });
  test('Signed-out users are not analyzed', () async {
    await prefs.setBool('isLoggedIn', false);
    expect(await SmsProcessingService(model).process(event), isTrue);
    expect(model.calls, 0);
  });
  test('Disabled protection and disabled SMS are respected', () async {
    await prefs.setBool('protection_activated', false);
    await SmsProcessingService(model).process(event);
    await prefs.setBool('protection_activated', true);
    await prefs.setBool('msg_detection', false);
    await SmsProcessingService(model).process(event);
    expect(model.calls, 0);
  });
  test('Queued messages cannot cross account boundaries', () async {
    event['owner'] = 'different-account';
    await SmsProcessingService(model).process(event);
    expect(model.calls, 0);
  });
  test(
    'Logout during inference prevents history writes and notifications',
    () async {
      model.duringPrediction = () async {
        await prefs.setBool('isLoggedIn', false);
      };
      expect(await SmsProcessingService(model).process(event), isTrue);
      expect(model.calls, 1);
      // SQLite/notifications have no mock handlers: either call would fail.
    },
  );
}
