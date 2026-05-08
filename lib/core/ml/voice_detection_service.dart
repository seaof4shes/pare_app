import 'dart:developer';
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'voice_mfcc_extractor.dart';

class VoiceDetectionService {
  Interpreter? _interpreter;
  final VoiceMfccExtractor _extractor = VoiceMfccExtractor();

  // ── Thresholds ────────────────────────────────────────────────────────────
  // fakeScore is sigmoid output: 0.0 = real/human, 1.0 = deepfake
  // Tune these after observing real _debugMode logs.
  // Start conservative: only flag if model is clearly confident.
  static const double _deepfakeThreshold = 0.65; // above → AI/Deepfake
  static const double _humanThreshold = 0.45; // below → Human
  //                                               between → Uncertain

  static const double _silenceRmsThreshold = 0.01;

  static const bool _debugMode = true;

  Future<void> loadModel() async {
    _interpreter ??= await Interpreter.fromAsset(
      'assets/models/voice_model.tflite',
    );
  }

  Future<Map<String, dynamic>> analyzeWavFile(String wavPath) async {
    await loadModel();

    final features = await _extractor.extractFromWav(wavPath);
    await _deleteFile(wavPath);

    if (_isSilence(features)) {
      return {
        'label': 'No Voice Detected',
        'result': -1,
        'confidence': 0.0,
        'fakeScore': 0.0,
        'safe': true,
        'action': 'Skipped – silence detected',
      };
    }

    // Shape: [1, 40, 157, 1]  →  matches model input_shape=(40, 157, 1)
    final input = features.reshape([1, 40, 157, 1]);
    final output = List.filled(1, 0.0).reshape([1, 1]);

    _interpreter!.run(input, output);

    final double fakeScore = (output[0][0] as num).toDouble();

    if (_debugMode) {
      log('════════════════════════════════════');
      log('  RAW fakeScore      : $fakeScore');
      log('  humanThreshold     : <= $_humanThreshold');
      log('  deepfakeThreshold  : >= $_deepfakeThreshold');
      if (fakeScore <= _humanThreshold) {
        log('  → HUMAN');
      } else if (fakeScore >= _deepfakeThreshold) {
        log('  → DEEPFAKE');
      } else {
        log('  → UNCERTAIN');
      }
      log('════════════════════════════════════');
    }

    if (fakeScore >= _deepfakeThreshold) {
      return {
        'label': 'AI / Deepfake Voice',
        'result': 1,
        'confidence': fakeScore * 100,
        'fakeScore': fakeScore,
        'safe': false,
        'action': 'Blocked',
      };
    } else if (fakeScore <= _humanThreshold) {
      return {
        'label': 'Human Voice',
        'result': 0,
        'confidence': (1.0 - fakeScore) * 100,
        'fakeScore': fakeScore,
        'safe': true,
        'action': 'Allowed',
      };
    } else {
      return {
        'label': 'Suspicious / Possible AI Voice',
        'result': 1,
        'confidence': fakeScore * 100,
        'fakeScore': fakeScore,
        'safe': false,
        'action': 'Alert Shown',
      };
    }
  }

  bool _isSilence(List<double> features) {
    double sumSq = 0;
    for (final v in features) {
      sumSq += v * v;
    }
    return (sumSq / features.length) < _silenceRmsThreshold;
  }

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void close() {
    _interpreter?.close();
  }
}
