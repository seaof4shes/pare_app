import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class SmsDetectionResult {
  final double scamProbability;
  final String label;
  final String riskLevel;

  SmsDetectionResult({
    required this.scamProbability,
    required this.label,
    required this.riskLevel,
  });
}

class SmsDetectionService {
  static const int sequenceLength = 80;

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
        .replaceAll(RegExp(r'http\S+'), '')
        .replaceAll(RegExp(r'\d+'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
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

  Future<SmsDetectionResult> predict(String message) async {
    await loadModel();

    final sequence = _textToSequence(message);

    final input = [sequence];
    final output = List.generate(1, (_) => List.filled(1, 0.0));

    _interpreter!.run(input, output);

    final probability = output[0][0];

    String label;
    String riskLevel;

    if (probability >= 0.75) {
      label = "Scam";
      riskLevel = "HIGH";
    } else if (probability >= 0.50) {
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
    );
  }

  void close() {
    _interpreter?.close();
  }
}
