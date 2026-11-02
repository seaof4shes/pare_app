import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/features/1_auth/screens/otp_screen.dart';

class ResendAuth implements FirebaseAuth {
  bool fail = false;
  int requests = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #verifyPhoneNumber) {
      requests++;
      if (fail) {
        (invocation.namedArguments[#verificationFailed]
            as PhoneVerificationFailed)(
          FirebaseAuthException(code: 'network-request-failed'),
        );
      } else {
        (invocation.namedArguments[#codeSent] as PhoneCodeSent)(
          'new-verification',
          1,
        );
      }
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets(
    'Resend starts a 30-second cooldown only on success and permits retry on failure',
    (tester) async {
      final auth = ResendAuth()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: OtpScreen(
            phone: '+639000000042',
            verificationId: 'fixture',
            auth: auth,
          ),
        ),
      );
      await tester.ensureVisible(find.text('Resend OTP'));
      await tester.tap(find.text('Resend OTP'));
      await tester.pump();
      expect(auth.requests, 1);
      expect(find.text('Resend OTP'), findsOneWidget);
      expect(find.text('30s'), findsNothing);
      auth.fail = false;
      await tester.tap(find.text('Resend OTP'));
      await tester.pump();
      expect(auth.requests, 2);
      expect(find.text('30s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Resend OTP'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Opening OTP entry does not start an unrequested resend countdown',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OtpScreen(
            phone: '+639000000042',
            verificationId: 'test-verification',
          ),
        ),
      );
      expect(find.text('Resend OTP'), findsOneWidget);
      expect(find.text('30s'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Resend OTP'), findsOneWidget);
      expect(find.text('25s'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
