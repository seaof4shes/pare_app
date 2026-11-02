import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'sms_risk_policy.dart';

class SmsDetectionResult {
  final double scamProbability;
  final String label;
  final String riskLevel;
  final int keywordScore;
  final double riskScore;
  final String explanation;
  final int modelVersion;

  SmsDetectionResult({
    required this.scamProbability,
    required this.label,
    required this.riskLevel,
    required this.keywordScore,
    required this.riskScore,
    required this.explanation,
    required this.modelVersion,
  });
}

class SmsDetectionService {
  static const sequenceLength = 200;
  static const defaultSmsModelVersion = 4;
  static const _bundleKey = 'pare_sms_bundle_v4';
  Interpreter? _interpreter;
  Map<String, int> _wordIndex = {};
  String? _loadedBundle;
  int _version = defaultSmsModelVersion;
  double _threshold = 0.7;
  Future<void>? _loading;

  Future<void> loadModel() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    final prefs = await PrivatePreferences.getInstance();
    final bundle = prefs.getString(_bundleKey);
    if (_interpreter != null && bundle == _loadedBundle) return;
    Interpreter? candidate;
    try {
      if (bundle != null) {
        final dir = Directory(bundle);
        final manifest =
            jsonDecode(await File('${dir.path}/manifest.json').readAsString())
                as Map<String, dynamic>;
        final model = File('${dir.path}/model.tflite');
        final vocabFile = File('${dir.path}/vocab.json');
        await _verify(manifest, model, vocabFile);
        candidate = Interpreter.fromFile(model);
        final vocab = _vocabulary(await vocabFile.readAsString());
        _validate(candidate, vocab.length);
        _replace(
          candidate,
          vocab,
          manifest['version'] as int,
          (manifest['cautionThreshold'] as num).toDouble(),
          bundle,
        );
        candidate = null;
        return;
      }
    } catch (e) {
      candidate?.close();
      log('Downloaded SMS bundle rejected; using bundled model: $e');
      await prefs.remove(_bundleKey);
    }
    final vocab = _vocabulary(
      await rootBundle.loadString('assets/models/vocab.json'),
    );
    final manifest =
        jsonDecode(
              await rootBundle.loadString('assets/models/sms_manifest.json'),
            )
            as Map<String, dynamic>;
    candidate = await Interpreter.fromAsset(
      'assets/models/sms_scam_model.tflite',
    );
    try {
      _validate(candidate, vocab.length);
      _replace(
        candidate,
        vocab,
        defaultSmsModelVersion,
        (manifest['cautionThreshold'] as num).toDouble(),
        null,
      );
    } catch (_) {
      candidate.close();
      rethrow;
    }
  }

  List<String> _vocabulary(String text) {
    final words = (jsonDecode(text) as List).cast<String>();
    if (words.length < 3 ||
        words[0] != '' ||
        words[1] != '[UNK]' ||
        words.toSet().length != words.length) {
      throw const FormatException('Invalid model vocabulary');
    }
    return words;
  }

  Future<void> _verify(
    Map<String, dynamic> manifest,
    File model,
    File vocab,
  ) async {
    if (manifest['version'] is! int ||
        manifest['version'] < defaultSmsModelVersion ||
        manifest['sequenceLength'] != sequenceLength ||
        manifest['preprocessing'] != 'ascii_url_number_v1' ||
        manifest['cautionThreshold'] is! num ||
        manifest['cautionThreshold'] < 0 ||
        manifest['cautionThreshold'] > 1) {
      throw const FormatException('Unsupported SMS model package');
    }
    if (sha256.convert(await model.readAsBytes()).toString() !=
            manifest['modelSha256'] ||
        sha256.convert(await vocab.readAsBytes()).toString() !=
            manifest['vocabSha256']) {
      throw const FormatException('SMS model package integrity check failed');
    }
  }

  void _validate(Interpreter model, int vocabularySize) {
    model.allocateTensors();
    final input = model.getInputTensor(0);
    final output = model.getOutputTensor(0);
    if (input.shape.join(',') != '1,200' ||
        output.shape.join(',') != '1,1' ||
        !input.type.toString().toLowerCase().contains('int32') ||
        !output.type.toString().toLowerCase().contains('float32')) {
      throw const FormatException('Incompatible SMS model tensors');
    }
    final result = [
      [0.0],
    ];
    model.run([List.filled(sequenceLength, vocabularySize - 1)], result);
    if (!result[0][0].isFinite || result[0][0] < 0 || result[0][0] > 1) {
      throw const FormatException('Invalid SMS model output');
    }
  }

  void _replace(
    Interpreter model,
    List<String> vocab,
    int version,
    double threshold,
    String? bundle,
  ) {
    _interpreter?.close();
    _interpreter = model;
    _wordIndex = {for (var i = 0; i < vocab.length; i++) vocab[i]: i};
    _version = version;
    _threshold = threshold;
    _loadedBundle = bundle;
  }

  Future<Map<String, dynamic>> downloadAndInstallModel({
    required String storagePath,
    required int modelVersion,
  }) async {
    Interpreter? validation;
    try {
      if (modelVersion <= await getInstalledModelVersion()) {
        throw StateError('Model is already installed or older');
      }
      final root = await getApplicationDocumentsDirectory();
      final directory = await Directory(
        '${root.path}/sms_models/v${modelVersion}_${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final prefix = storagePath.replaceFirst(RegExp(r'\.tflite$'), '');
      final storage = FirebaseStorage.instance;
      final model = File('${directory.path}/model.tflite');
      final vocabFile = File('${directory.path}/vocab.json');
      final manifestFile = File('${directory.path}/manifest.json');
      await storage.ref(storagePath).writeToFile(model);
      await storage.ref('${prefix}_vocab.json').writeToFile(vocabFile);
      await storage.ref('${prefix}_manifest.json').writeToFile(manifestFile);
      final manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      if (manifest['version'] != modelVersion) {
        throw const FormatException('Version mismatch');
      }
      await _verify(manifest, model, vocabFile);
      final vocab = _vocabulary(await vocabFile.readAsString());
      validation = Interpreter.fromFile(model);
      _validate(validation, vocab.length);
      final prefs = await PrivatePreferences.getInstance();
      // Single pointer commit: interrupted downloads never replace the active package.
      if (!await prefs.setString(_bundleKey, directory.path)) {
        throw StateError('Could not activate SMS package');
      }
      return {'success': true, 'modelVersion': modelVersion};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    } finally {
      validation?.close();
    }
  }

  Future<int> getInstalledModelVersion() async {
    await loadModel();
    return _version;
  }

  Future<SmsDetectionResult> predict(String message) async {
    await loadModel();
    final cleaned = message
        .toLowerCase()
        .replaceAll(RegExp(r'http\S+|www\S+'), ' urltoken ')
        .replaceAll(RegExp(r'\d+'), ' numtoken ')
        .replaceAll(RegExp(r'[^a-z0-9_\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tokens = cleaned.isEmpty ? <String>[] : cleaned.split(' ');
    final input = List<int>.filled(sequenceLength, 0);
    for (var i = 0; i < tokens.length && i < sequenceLength; i++) {
      input[i] = _wordIndex[tokens[i]] ?? 1;
    }
    final output = [
      [0.0],
    ];
    _interpreter!.run([input], output);
    final probability = output[0][0];
    if (!probability.isFinite || probability < 0 || probability > 1) {
      throw StateError('Invalid SMS prediction');
    }
    final result = SmsRiskPolicy.assess(
      message,
      probability,
      cautionThreshold: _threshold,
    );
    return SmsDetectionResult(
      scamProbability: probability,
      label: result.label,
      riskLevel: result.riskLevel,
      keywordScore: result.evidenceScore,
      riskScore: result.riskScore,
      explanation: result.explanation,
      modelVersion: _version,
    );
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }
}
