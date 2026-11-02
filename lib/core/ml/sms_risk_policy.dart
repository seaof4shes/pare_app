/// Contextual rules complement the bundled model, which can overrate ordinary
/// reminders. Scores are risk indicators, not calibrated probabilities.
class SmsRiskAssessment {
  final String label;
  final String riskLevel;
  final int evidenceScore;
  final double riskScore;
  final String explanation;

  const SmsRiskAssessment(
    this.label,
    this.riskLevel,
    this.evidenceScore,
    this.riskScore,
    this.explanation,
  );
}

class SmsRiskPolicy {
  static SmsRiskAssessment assess(
    String message,
    double modelScore, {
    double cautionThreshold = 0.7,
  }) {
    final text = message.toLowerCase().replaceAll(RegExp('[’‘]'), "'");
    bool has(String pattern) => RegExp(pattern).hasMatch(text);

    // Remove only explicit safety instructions from credential-request checks.
    // Keep the rest: a scam can include a safety disclaimer and still ask for OTP.
    final requests = text.replaceAll(
      RegExp(
        r"\b(?:do not|don't|never|huwag|wag)\s+(?:ever\s+)?(?:share|send|give|provide|disclose|ibigay|ipadala)\s+(?:your\s+|ang\s+)?(?:otp|password|pin|verification code|one[ -]time password)\b(?:\s+(?:or|and)\s+(?:password|pin|otp)\b)?",
      ),
      ' ',
    );
    final credentialRequest = RegExp(
      r'\b(?:share|send|give|provide|tell|reply|submit|enter|input|disclose|ibigay|ipadala|ilagay)\b[^.!?;\n]{0,65}\b(?:otp|one[ -]time (?:password|pin|code)|password|pin|verification code|security code)\b',
    ).hasMatch(requests);
    final discloseCredential = RegExp(
      r'\b(?:share|send|give|provide|tell|reply|disclose|ibigay|ipadala)\b[^.!?;\n]{0,65}\b(?:otp|one[ -]time (?:password|pin|code)|password|pin|verification code|security code)\b',
    ).hasMatch(requests);
    final link = has(
      r'\b(?:https?://|www\.)\S+|\b[a-z0-9][a-z0-9.-]*\.(?:com|ph|net|org|ly|co|xyz|top|site|info)\b',
    );
    final accountAction = has(
      r'\b(?:verify|validate|confirm|reactivate|unlock|update)\b.{0,45}\b(?:account|identity|banking|wallet|details)\b',
    );
    final threat = has(
      r'\b(?:suspend(?:ed)?|restrict(?:ed)?|locked|frozen|deactivat(?:e|ed|ion)|final warning)\b',
    );
    final urgency = has(
      r'\b(?:urgent|immediately|act now|within \d+ hours?)\b',
    );
    final prize = has(
      r'\b(?:prize|winner|you (?:have )?won|nanalo|panalo|premyo)\b',
    );
    final payment = has(
      r'\b(?:send money|transfer money|pay now|payment required|processing fee|claim fee|advance fee|magbayad)\b',
    );
    final personalData = RegExp(
      r'\b(?:send|submit|provide|enter)\b.{0,50}\b(?:personal information|account number|card number|cvv)\b',
    ).hasMatch(requests);

    final reasons = <String>[];
    if (credentialRequest) {
      reasons.add('Requests a password, PIN, OTP, or verification code.');
    }
    if (link && accountAction) {
      reasons.add('Combines an account verification request with a web link.');
    }
    if (threat && (accountAction || link)) {
      reasons.add(
        'Uses an account restriction or suspension threat with a requested action.',
      );
    }
    if (prize && payment) {
      reasons.add('Requests payment in connection with a prize.');
    }
    if (personalData) {
      reasons.add('Requests personal or financial information.');
    }
    if (payment && link) {
      reasons.add('Combines a payment request with a web link.');
    }
    var evidence = 0;
    if (credentialRequest) evidence += 6;
    if (link && accountAction) evidence += 4;
    if (threat && (accountAction || link)) evidence += 4;
    if (urgency && (accountAction || payment || credentialRequest)) {
      evidence += 2;
    }
    if (prize && (payment || personalData)) evidence += 6;
    if (personalData) evidence += 3;
    if (payment && link) evidence += 3;

    final probability = modelScore.isFinite ? modelScore.clamp(0.0, 1.0) : 0.5;
    final high =
        discloseCredential ||
        (credentialRequest && (link || threat || accountAction)) ||
        (prize && payment) ||
        (evidence >= 8 && probability >= 0.5);
    if (high) {
      return SmsRiskAssessment(
        'Scam',
        'HIGH',
        evidence.clamp(0, 20),
        probability,
        '${reasons.join(' ')} Do not send codes or money; verify through an independently obtained contact.',
      );
    }
    if (evidence >= 3 ||
        (text.trim().isNotEmpty && probability >= cautionThreshold)) {
      return SmsRiskAssessment(
        'Suspicious',
        'MEDIUM',
        evidence.clamp(0, 20),
        probability,
        reasons.isEmpty
            ? 'The model detected patterns associated with spam or scams, but no strong harmful request was identified. Verify the message before acting.'
            : '${reasons.join(' ')} Verify the request before acting.',
      );
    }
    // A link, brand, survey, promotion, or an unreliable model score alone
    // cannot establish phishing. No survey/brand is explicitly allowlisted.
    return SmsRiskAssessment(
      'Legit',
      'LOW',
      evidence,
      probability,
      'No strong suspicious request was detected. This does not verify the sender or guarantee that the message is safe.',
    );
  }
}
