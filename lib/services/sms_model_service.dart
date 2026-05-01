import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

class SmsModelService {
  late Interpreter _interpreter;
  late Map<String, dynamic> _vocab;

  static const int maxLength = 50;

  Future<void> loadModel() async {
    _interpreter = await Interpreter.fromAsset(
      'assets/models/sms_scam_model.tflite',
    );

    final vocabString = await rootBundle.loadString('assets/models/vocab.json');

    final vocabData = jsonDecode(vocabString);

    if (vocabData is List) {
      _vocab = {
        for (int i = 0; i < vocabData.length; i++)
          vocabData[i].toString(): i + 1,
      };
    } else {
      _vocab = Map<String, dynamic>.from(vocabData);
    }

    debugPrint('SMS model loaded successfully');
    debugPrint('Vocab size: ${_vocab.length}');
  }

  List<int> _textToSequence(String text) {
    final cleaned = text.toLowerCase().replaceAll(
      RegExp(r'[^a-zA-Z0-9\s]'),
      '',
    );

    final words = cleaned.split(RegExp(r'\s+'));

    final sequence = List<int>.filled(maxLength, 0);

    for (int i = 0; i < words.length && i < maxLength; i++) {
      final word = words[i];

      if (_vocab.containsKey(word)) {
        sequence[i] = (_vocab[word] as num).toInt();
      }
    }

    return sequence;
  }

  Future<Map<String, dynamic>> predictSms(String message) async {
    final input = [_textToSequence(message)];

    final output = List.generate(1, (_) => List<double>.filled(1, 0));

    _interpreter.run(input, output);

    final score = output[0][0];
    final isScam = score <= 0.10;

    return {'label': isScam ? 'scam' : 'legit', 'score': score};
  }

  void close() {
    _interpreter.close();
  }
}
