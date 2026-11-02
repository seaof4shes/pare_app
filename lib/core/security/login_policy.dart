/// Closing or backgrounding the app does not revoke a verified device session.
bool requiresLoginOtp({
  required bool localAccountExists,
  required String phone,
  required String? authenticatedPhone,
  required bool verificationRequired,
}) =>
    !localAccountExists || verificationRequired || authenticatedPhone != phone;
