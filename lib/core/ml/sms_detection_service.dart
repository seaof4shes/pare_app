import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class SmsDetectionResult {
  final double scamProbability;
  final String label;
  final String riskLevel;
  final int keywordScore;

  SmsDetectionResult({
    required this.scamProbability,
    required this.label,
    required this.riskLevel,
    required this.keywordScore,
  });
}

class SmsDetectionService {
  static const int sequenceLength = 200;

  Interpreter? _interpreter;
  Map<String, int> _wordIndex = {};
  bool _isLoaded = false;

  Future<void> loadModel() async {
    if (_isLoaded) return;

    _interpreter = await Interpreter.fromAsset(
      'assets/models/sms_scam_model.tflite',
    );

    final vocabString = await rootBundle.loadString('assets/models/vocab.json');
    final List<dynamic> vocabList = jsonDecode(vocabString);

    _wordIndex = {
      for (int i = 0; i < vocabList.length; i++) vocabList[i].toString(): i,
    };

    _isLoaded = true;
  }

  String _cleanText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'http\S+|www\S+'), ' urltoken ')
        .replaceAll(RegExp(r'\d+'), ' numtoken ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<int> _textToSequence(String message) {
    final cleaned = _cleanText(message);
    final words = cleaned.split(' ');

    final sequence = List<int>.filled(sequenceLength, 0);

    for (int i = 0; i < words.length && i < sequenceLength; i++) {
      sequence[i] = _wordIndex[words[i]] ?? 1;
    }

    return sequence;
  }

  int _keywordScore(String message) {
    final text = message.toLowerCase();
    int score = 0;

    // Links / hidden destinations
    if (text.contains('http') ||
        text.contains('www.') ||
        text.contains('.com')) {
      score += 3;
    }

    if (text.contains('bit.ly') ||
        text.contains('tinyurl') ||
        text.contains('link')) {
      score += 2;
    }

    // Generic phishing actions
    if (text.contains('verify')) {
      score += 2;
    }

    if (text.contains('confirm')) {
      score += 2;
    }

    if (text.contains('validate')) {
      score += 2;
    }

    if (text.contains('update')) {
      score += 1;
    }

    if (text.contains('login')) {
      score += 1;
    }

    if (text.contains('sign in')) {
      score += 1;
    }

    if (text.contains('click')) {
      score += 1;
    }

    if (text.contains('tap')) {
      score += 1;
    }

    if (text.contains('enter your')) {
      score += 2;
    }

    if (text.contains('submit')) {
      score += 1;
    }

    // Account / identity targets
    if (text.contains('account')) {
      score += 1;
    }

    if (text.contains('identity')) {
      score += 2;
    }

    if (text.contains('password')) {
      score += 3;
    }

    if (text.contains('pin')) {
      score += 3;
    }

    if (text.contains('otp') || text.contains('one-time password')) {
      score += 3;
    }

    if (text.contains('do not share')) {
      score += 3;
    }

    if (text.contains('account number')) {
      score += 2;
    }

    if (text.contains('personal information')) {
      score += 3;
    }

    if (text.contains('details')) {
      score += 1;
    }

    // Urgency / fear tactics
    if (text.contains('urgent')) {
      score += 2;
    }

    if (text.contains('immediately')) {
      score += 2;
    }

    if (text.contains('now')) {
      score += 1;
    }

    if (text.contains('within 12 hours')) {
      score += 2;
    }

    if (text.contains('limited time')) {
      score += 2;
    }

    if (text.contains('act now')) {
      score += 2;
    }

    if (text.contains('failure to act')) {
      score += 2;
    }

    if (text.contains('final warning')) {
      score += 3;
    }

    // Account threats
    if (text.contains('restricted')) {
      score += 2;
    }

    if (text.contains('suspended')) {
      score += 2;
    }

    if (text.contains('deactivation')) {
      score += 2;
    }

    if (text.contains('blocked')) {
      score += 1;
    }

    if (text.contains('locked')) {
      score += 2;
    }

    if (text.contains('frozen')) {
      score += 2;
    }

    if (text.contains('fund freezing')) {
      score += 3;
    }

    if (text.contains('unauthorized')) {
      score += 2;
    }

    if (text.contains('suspicious login')) {
      score += 3;
    }

    if (text.contains('security alert')) {
      score += 2;
    }

    // PH banks / wallets
    if (text.contains('bank')) {
      score += 1;
    }

    if (text.contains('bdo')) {
      score += 2;
    }

    if (text.contains('bpi')) {
      score += 2;
    }

    if (text.contains('metrobank')) {
      score += 2;
    }

    if (text.contains('unionbank')) {
      score += 2;
    }

    if (text.contains('gcash')) {
      score += 2;
    }

    if (text.contains('maya')) {
      score += 2;
    }

    if (text.contains('paymaya')) {
      score += 2;
    }

    if (text.contains('wallet')) {
      score += 1;
    }

    if (text.contains('transaction')) {
      score += 1;
    }

    // Rewards / fake promos
    if (text.contains('congratulations')) {
      score += 3;
    }

    if (text.contains('congrats')) {
      score += 2;
    }

    if (text.contains('you won')) {
      score += 3;
    }

    if (text.contains('winner')) {
      score += 2;
    }

    if (text.contains('prize')) {
      score += 2;
    }

    if (text.contains('claim')) {
      score += 2;
    }

    if (text.contains('reward')) {
      score += 2;
    }

    if (text.contains('free')) {
      score += 1;
    }

    if (text.contains('bonus')) {
      score += 1;
    }

    if (text.contains('cash')) {
      score += 1;
    }

    if (text.contains('₱') || text.contains('php')) {
      score += 2;
    }

    // Tagalog / Taglish scam patterns
    if (text.contains('pindutin')) {
      score += 2;
    }

    if (text.contains('i-click') || text.contains('iclick')) {
      score += 2;
    }

    if (text.contains('mag login')) {
      score += 2;
    }

    if (text.contains('mag-register') || text.contains('mag register')) {
      score += 2;
    }

    if (text.contains('kunin')) {
      score += 1;
    }

    if (text.contains('claim mo')) {
      score += 2;
    }

    if (text.contains('panalo')) {
      score += 2;
    }

    if (text.contains('nanalo')) {
      score += 2;
    }

    if (text.contains('premyo')) {
      score += 2;
    }

    if (text.contains('libreng')) {
      score += 1;
    }

    if (text.contains('load')) {
      score += 1;
    }

    if (text.contains('ayuda')) {
      score += 1;
    }

    // Strong phrase combinations
    if (text.contains('verify') && text.contains('account')) {
      score += 2;
    }

    if (text.contains('account') && text.contains('suspended')) {
      score += 2;
    }

    if (text.contains('account') && text.contains('locked')) {
      score += 2;
    }

    if (text.contains('otp') && text.contains('share')) {
      score += 2;
    }

    if (text.contains('claim') &&
        (text.contains('prize') || text.contains('reward'))) {
      score += 2;
    }

    if (text.contains('urgent') &&
        (text.contains('account') || text.contains('verify'))) {
      score += 2;
    }

    return score.clamp(0, 20);
  }

  Future<SmsDetectionResult> predict(String message) async {
    await loadModel();

    final sequence = _textToSequence(message);

    final input = [sequence];
    final output = List.generate(1, (_) => List.filled(1, 0.0));

    _interpreter!.run(input, output);

    final probability = output[0][0];
    final score = _keywordScore(message);

    final wordCount = _cleanText(
      message,
    ).split(' ').where((word) => word.trim().isNotEmpty).length;

    if (wordCount <= 3 && score == 0) {
      return SmsDetectionResult(
        scamProbability: probability,
        label: "Legit",
        riskLevel: "LOW",
        keywordScore: score,
      );
    }

    String label;
    String riskLevel;

    // HYBRID DECISION
    if (probability >= 0.75 || score >= 8) {
      label = "Scam";
      riskLevel = "HIGH";
    } else if (probability >= 0.50 || score >= 4) {
      label = "Suspicious";
      riskLevel = "MEDIUM";
    } else {
      label = "Legit";
      riskLevel = "LOW";
    }

    return SmsDetectionResult(
      scamProbability: probability,
      label: label,
      riskLevel: riskLevel,
      keywordScore: score,
    );
  }

  void close() {
    _interpreter?.close();
  }
}
