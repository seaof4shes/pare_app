import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/core/ml/sms_risk_policy.dart';

void main() {
  const toyotaSurvey =
      'Happy Day!  This is from Customer Relations Department of Toyota Shaw Inc.   We would like to conduct a quick o know your experience from your previous visit with us.  We would appreciate your s this will be used for the improvement of our operations.  1. How likely are you to recommend our Dealer to your family and friends? (1-10, 1 is the Lowest and 10 is the Highest)  2. What are the Particulars things that make you recommend us so we could continue providing it to our customers? What are the particular things that we need to improve on our operations?  3. How satisfied are you with the overall service provided? (1-5, 1 very dissatisfied and 5 is very satisfied)  Q1. Was the PMS/Repair done properly? Q2. Was the Promise time to complete the service met? Q3. Was the Promise time reasonable?  We would like to inform you that we have our Toyota App, and we highly encourage you to register for easier transaction on your next visit. You may download it in your App Store or Google Play store, just search for MyToyota.  Should you need any assistance, please feel free to contact us.  Thank you!  **Please be informed that ToyotaShaw Inc. complies with Data Privacy Act of 2012 to ensure the confidentiality and safety of your information**  ';

  test('Exact defense Toyota survey has no harmful-request evidence', () {
    for (final score in [0.0, 0.1, 0.5]) {
      final result = SmsRiskPolicy.assess(toyotaSurvey, score);
      expect(result.label, 'Legit');
      expect(result.riskLevel, 'LOW');
      expect(result.evidenceScore, 0);
      expect(result.riskScore, score);
    }
  });

  test('Survey text does not conceal an appended OTP request', () {
    final result = SmsRiskPolicy.assess(
      '$toyotaSurvey Send your OTP to our agent to complete the survey.',
      0.1,
    );
    expect(result.riskLevel, 'HIGH');
  });

  test('Unrecognized model-positive message requires review', () {
    expect(
      SmsRiskPolicy.assess('An unexpected offer awaits you', 0.95).riskLevel,
      'MEDIUM',
    );
  });

  test('Safety disclaimer cannot swallow later request in same sentence', () {
    expect(
      SmsRiskPolicy.assess(
        'Do not share your OTP with strangers but send your OTP to us',
        0.1,
      ).riskLevel,
      'HIGH',
    );
  });

  group('Legitimate SMS false alarms', () {
    final messages = [
      'Toyota: Thank you for visiting. Please complete our customer satisfaction survey at https://example.com/survey. Confirm your appointment feedback.',
      'Your shopping reward is ready. Claim your voucher at https://example.com.',
      'Reminder: Your appointment is scheduled for Friday at 10:00 AM. Please contact our service desk if you need to reschedule.',
      'BDO: Your OTP code is 482193. Do not share your OTP with anyone.',
      'Your one-time password is 123456. Never share your password or PIN.',
      'GCash: Your transaction was successful. PHP 500 sent.',
      'Congratulations on your graduation!',
      'Huwag ibigay ang OTP mo sa iba.',
      '',
    ];
    for (final message in messages) {
      test(message, () {
        final result = SmsRiskPolicy.assess(message, 0.1);
        expect(result.riskLevel, 'LOW');
        expect(result.riskScore, lessThan(0.4));
      });
    }
  });

  group('Phishing remains detectable', () {
    final messages = [
      'URGENT: Your bank account will be suspended. Verify your account immediately using this link and enter your password and OTP.',
      'Send your OTP to our agent.',
      'Toyota survey: Please enter your password at https://example.com.',
      'You won a car! Pay a processing fee to claim your prize.',
      'Do not share your OTP with anyone. Send your OTP to our agent now.',
      'Ibigay ang OTP mo para ma-verify ang account.',
      'Send OTP',
    ];
    for (final message in messages) {
      test(message, () {
        final result = SmsRiskPolicy.assess(message, 0.1);
        expect(result.riskLevel, 'HIGH');
        expect(result.riskScore, 0.1);
      });
    }
  });

  test('Account verification link requires caution', () {
    final result = SmsRiskPolicy.assess(
      'Please verify your account at https://example.com',
      0.2,
    );
    expect(result.riskLevel, 'MEDIUM');
    expect(result.riskScore, 0.2);
  });
}
