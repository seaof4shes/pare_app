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

    final requests = text.replaceAll(
      RegExp(
        r"\b(?:do not|don't|never|huwag|wag)\s+(?:ever\s+)?(?:share|send|give|provide|disclose|ibigay|ipadala)\s+(?:your\s+|ang\s+)?(?:otp|password|pin|verification code|one[ -]time password)\b(?:\s+(?:or|and)\s+(?:password|pin|otp)\b)?",
      ),
      ' ',
    );
    final credentialMatch = RegExp(
      r'\b(?:share|send|give|provide|tell|reply|submit|enter|input|disclose|ibigay|ipadala|ilagay)\b[^.!?;\n]{0,65}\b(otp|one[ -]time (?:password|pin|code)|password|pin|verification code|security code)\b',
    ).firstMatch(requests);
    final credentialRequest = credentialMatch != null;
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
    final urgencyMatch = RegExp(
      r'\b(?:urgent|immediately|act now|within \d+ hours?)\b',
    ).firstMatch(text);
    final urgency = urgencyMatch != null;
    final prize = has(
      r'\b(?:prize|winner|you (?:have )?won|nanalo|panalo|premyo)\b',
    );
    final payment = has(
      r'\b(?:send money|transfer money|pay now|payment required|processing fee|claim fee|advance fee|magbayad)\b',
    );
    final personalMatch = RegExp(
      r'\b(?:send|submit|provide|enter)\b.{0,50}\b(personal information|account number|card number|cvv)\b',
    ).firstMatch(requests);
    final personalData = personalMatch != null;

    final reasons = <String>[];
    final signals = <String>[];
    void reason(String signal, String detail) {
      signals.add(signal);
      reasons.add(detail);
    }

    if (credentialRequest) {
      final credential = credentialMatch.group(1)!.toUpperCase();
      reason(
        'asks for your $credential',
        'Sensitive code or password request: asks you to share or enter your $credential. Giving it to someone else can let them access your account or authorize a transaction.',
      );
    }
    if (link && accountAction) {
      reason(
        'asks for account verification through a link',
        'Account action with a link: asks you to verify, confirm or update account details and includes a web address. This combination can lead you to a fake sign-in page; the link has not been verified as malicious.',
      );
    }
    if (threat && (accountAction || link)) {
      reason(
        'threatens account access unless you act',
        'Account threat: mentions a restriction, suspension or similar warning together with an account action or link. This can pressure you into acting without checking the sender.',
      );
    }
    if (prize && payment) {
      reason(
        'asks for payment to claim a prize',
        'Prize payment: combines a prize or winning claim with a payment or fee. Paying to receive a supposed prize is a strong scam warning sign.',
      );
    } else if (prize && personalData) {
      reason(
        'links a prize to a request for personal details',
        'Prize and personal details: combines a winning claim with a request for personal or financial information. The offer may be used to collect your details.',
      );
    }
    if (personalData) {
      final information = personalMatch.group(1)!;
      reason(
        'requests your $information',
        'Personal or financial details: asks you to send, submit, provide or enter your $information. These details may be misused if the sender is not genuine.',
      );
    }
    if (payment && link) {
      reason(
        'combines a payment request with a link',
        'Payment with a link: asks for money or a fee and includes a web address. Confirm the request independently before paying.',
      );
    }
    if (urgency && (accountAction || payment || credentialRequest)) {
      reason(
        'pressures you to act quickly',
        'Urgency: uses "${urgencyMatch.group(0)}" alongside an account action, payment or code/password request. The pressure to act quickly adds to the risk; urgency alone does not establish a scam.',
      );
    }
    String detailed(String level, String advice) =>
        '$level: ${signals.take(3).join('; ')}.\n\nDetected signs:\n${reasons.map((r) => '• $r').join('\n\n')}\n\n$advice';
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
        detailed(
          'High risk',
          'These harmful-request patterns triggered a high-risk warning. Do not share codes or send money. Verify through a contact you obtain independently, not one supplied in this message.',
        ),
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
            ? 'Needs review: the model flagged this message, but no specific harmful request was identified.\n\nThe model found patterns associated with spam or scams. This is a model-based warning, not proof that a particular phrase or sender is fraudulent. Confirm the message through an official contact before acting.'
            : detailed(
                'Needs review',
                'These signs require caution, but did not meet the high-risk decision rules. Confirm the sender and purpose before sharing information, opening links or making a payment.',
              ),
      );
    }

    return SmsRiskAssessment(
      'Legit',
      'LOW',
      evidence,
      probability,
      'Low risk: no strong suspicious request was detected.\n\nThe message did not meet the high-risk or review conditions in the current checks. Low risk does not verify the sender or guarantee safety. A familiar brand or survey format is not proof of legitimacy; verify any unexpected request before acting.',
    );
  }
}
