import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/core/security/login_policy.dart';

void main() {
  const phone = '+630000000042';
  test(
    'Fresh installation requires OTP even with an authenticated Firebase user',
    () {
      expect(
        requiresLoginOtp(
          localAccountExists: false,
          phone: phone,
          authenticatedPhone: phone,
          verificationRequired: false,
        ),
        isTrue,
      );
    },
  );
  test('Returning verified device uses MPIN without another OTP', () {
    expect(
      requiresLoginOtp(
        localAccountExists: true,
        phone: phone,
        authenticatedPhone: phone,
        verificationRequired: false,
      ),
      isFalse,
    );
  });
  test(
    'Explicit logout or missing/mismatched Firebase session requires OTP',
    () {
      for (final authenticated in [null, '+630000000099']) {
        expect(
          requiresLoginOtp(
            localAccountExists: true,
            phone: phone,
            authenticatedPhone: authenticated,
            verificationRequired: false,
          ),
          isTrue,
        );
      }
      expect(
        requiresLoginOtp(
          localAccountExists: true,
          phone: phone,
          authenticatedPhone: phone,
          verificationRequired: true,
        ),
        isTrue,
      );
    },
  );
}
