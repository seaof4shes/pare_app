import 'dart:developer';
import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'voice_mfcc_extractor.dart';

class VoiceDetectionService {
  Interpreter? _interpreter;
  final VoiceMfccExtractor _extractor = VoiceMfccExtractor();

  static const double _deepfakeThreshold = 0.65;
  static const double _humanThreshold = 0.45;
  static const double _silenceThreshold = 0.01;

  // ── Set to false before releasing to production ──
  static const bool _debugMode = true;

  Future<void> loadModel() async {
    _interpreter ??= await Interpreter.fromAsset(
      'assets/models/voice_model.tflite',
    );
  }

  Future<Map<String, dynamic>> analyzeWavFile(String wavPath) async {
    await loadModel();

    // Extract features BEFORE deleting the file
    final features = await _extractor.extractFromWav(wavPath);

    // NOW safe to delete
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

    final input = features.reshape([1, 40, 157, 1]);
    final output = List.filled(1, 0.0).reshape([1, 1]);

    _interpreter!.run(input, output);

    final double fakeScore = output[0][0];

    // ── DEBUG: log raw score to help tune thresholds ──
    if (_debugMode) {
      log('════════════════════════════════════');
      log('  RAW fakeScore  : $fakeScore');
      log('  humanThreshold : <= $_humanThreshold');
      log('  fakeThreshold  : >= $_deepfakeThreshold');
      if (fakeScore <= _humanThreshold) {
        log('  → HUMAN');
      } else if (fakeScore >= _deepfakeThreshold) {
        log('  → DEEPFAKE');
      } else {
        log('  → UNCERTAIN ($_humanThreshold} < score < $_deepfakeThreshold)');
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
        'action': 'Alert Shown',
      };
    } else if (fakeScore <= _humanThreshold) {
      return {
        'label': 'Human Voice',
        'result': 0,
        'confidence': (1 - fakeScore) * 100,
        'fakeScore': fakeScore,
        'safe': true,
        'action': 'Allowed',
      };
    } else {
      return {
        'label': 'Uncertain – possibly human',
        'result': 0,
        'confidence': (1 - fakeScore) * 100,
        'fakeScore': fakeScore,
        'safe': true,
        'action': 'Allowed (low confidence)',
      };
    }
  }

  bool _isSilence(List<double> features) {
    double sumSq = 0;
    for (final v in features) {
      sumSq += v * v;
    }
    final rms = sumSq / features.length;
    return rms < _silenceThreshold;
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // ignore cleanup errors
    }
  }

  void close() {
    _interpreter?.close();
  }
}
