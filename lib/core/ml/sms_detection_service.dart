import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const String _assetModelPath = 'assets/models/sms_scam_model.tflite';

  static const String _assetVocabPath = 'assets/models/vocab.json';

  static const String _activeModelPathKey = 'pare_active_sms_model_path';

  static const String _smsModelVersionKey = 'pare_installed_sms_model_version';

  static const int defaultSmsModelVersion = 1;

  Interpreter? _interpreter;

  Map<String, int> _wordIndex = {};

  bool _isLoaded = false;

  // ============================================================
  // MODEL LOADING
  // ============================================================

  Future<void> loadModel() async {
    if (_isLoaded) return;

    final prefs = await SharedPreferences.getInstance();

    final savedModelPath = prefs.getString(_activeModelPathKey);

    if (savedModelPath != null && savedModelPath.isNotEmpty) {
      final savedModelFile = File(savedModelPath);

      if (await savedModelFile.exists()) {
        try {
          log(
            '📩 Loading downloaded SMS model: '
            '$savedModelPath',
          );

          _interpreter = Interpreter.fromFile(savedModelFile);

          log('✅ Downloaded SMS model loaded successfully.');

          await _loadVocabulary();

          _isLoaded = true;
          return;
        } catch (e, stackTrace) {
          log('⚠️ Downloaded SMS model could not be loaded: $e');

          log('⚠️ Stack trace: $stackTrace');

          // Remove invalid active model reference.
          await prefs.remove(_activeModelPathKey);

          // Continue to bundled model.
        }
      } else {
        await prefs.remove(_activeModelPathKey);
      }
    }

    log('📩 Loading bundled SMS model...');

    _interpreter = await Interpreter.fromAsset(_assetModelPath);

    await _loadVocabulary();

    _isLoaded = true;

    log('✅ Bundled SMS model loaded successfully.');
  }

  Future<void> _loadVocabulary() async {
    final vocabString = await rootBundle.loadString(_assetVocabPath);

    final List<dynamic> vocabList = jsonDecode(vocabString);

    _wordIndex = {
      for (int i = 0; i < vocabList.length; i++) vocabList[i].toString(): i,
    };

    log(
      '📚 SMS vocabulary loaded: '
      '${_wordIndex.length} words',
    );
  }

  // ============================================================
  // SMS MODEL UPDATE
  // ============================================================

  Future<Map<String, dynamic>> downloadAndInstallModel({
    required String storagePath,
    required int modelVersion,
  }) async {
    log('📩 Starting SMS model update...');
    log('☁️ Storage path: $storagePath');
    log('📦 Target model version: $modelVersion');

    File? tempFile;

    try {
      final directory = await getApplicationDocumentsDirectory();

      final modelsDirectory = Directory('${directory.path}/sms_models');

      if (!await modelsDirectory.exists()) {
        await modelsDirectory.create(recursive: true);
      }

      tempFile = File(
        '${modelsDirectory.path}/sms_scam_model_v${modelVersion}_temp.tflite',
      );

      final activeFile = File(
        '${modelsDirectory.path}/sms_scam_model_v$modelVersion.tflite',
      );

      log('📁 Temporary model path: ${tempFile.path}');

      log('📁 Active model path: ${activeFile.path}');

      // --------------------------------------------------------
      // 1. DOWNLOAD FROM FIREBASE STORAGE
      // --------------------------------------------------------

      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      log('⬇️ Downloading SMS model...');

      await storageRef.writeToFile(tempFile);

      if (!await tempFile.exists()) {
        throw Exception('Downloaded SMS model file does not exist.');
      }

      final fileSize = await tempFile.length();

      log(
        '📦 Downloaded SMS model size: '
        '$fileSize bytes',
      );

      if (fileSize <= 0) {
        throw Exception('Downloaded SMS model is empty.');
      }

      // --------------------------------------------------------
      // 2. VERIFY THAT THE MODEL CAN ACTUALLY LOAD
      // --------------------------------------------------------

      log('🔍 Validating downloaded SMS model...');

      final validationInterpreter = Interpreter.fromFile(tempFile);

      validationInterpreter.allocateTensors();

      final inputTensor = validationInterpreter.getInputTensor(0);

      final outputTensor = validationInterpreter.getOutputTensor(0);

      final inputShape = inputTensor.shape;
      final outputShape = outputTensor.shape;

      final inputType = inputTensor.type.toString();
      final outputType = outputTensor.type.toString();

      log(
        '📥 Downloaded model input: '
        '$inputShape $inputType',
      );

      log(
        '📤 Downloaded model output: '
        '$outputShape $outputType',
      );

      final isCompatible =
          inputShape.length == 2 &&
          inputShape[0] == 1 &&
          inputShape[1] == sequenceLength &&
          outputShape.length == 2 &&
          outputShape[0] == 1 &&
          outputShape[1] == 1 &&
          inputType.toLowerCase().contains('int32') &&
          outputType.toLowerCase().contains('float32');

      validationInterpreter.close();

      if (!isCompatible) {
        throw Exception(
          'Downloaded SMS model is incompatible with '
          'the current P.A.R.E. SMS detection service.',
        );
      }

      log('✅ Downloaded SMS model passed compatibility check.');

      if (!isCompatible) {
        throw Exception(
          'Downloaded SMS model is incompatible with '
          'the current P.A.R.E. SMS detection service.',
        );
      }

      log('✅ Downloaded SMS model passed compatibility check.');

      // --------------------------------------------------------
      // 3. MOVE VERIFIED MODEL TO ACTIVE MODEL LOCATION
      // --------------------------------------------------------

      if (await activeFile.exists()) {
        await activeFile.delete();
      }

      await tempFile.rename(activeFile.path);

      log(
        '✅ SMS model saved successfully: '
        '${activeFile.path}',
      );

      // --------------------------------------------------------
      // 4. UPDATE STORED MODEL INFORMATION
      // --------------------------------------------------------

      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_activeModelPathKey, activeFile.path);

      await prefs.setInt(_smsModelVersionKey, modelVersion);

      log(
        '💾 Installed SMS model version: '
        'v$modelVersion',
      );

      // --------------------------------------------------------
      // 5. RELOAD INTERPRETER
      // --------------------------------------------------------

      _interpreter?.close();
      _interpreter = null;
      _isLoaded = false;

      await loadModel();

      log('🎉 SMS model v$modelVersion is now active.');

      return {
        'success': true,
        'modelVersion': modelVersion,
        'path': activeFile.path,
        'message': 'SMS detection model updated successfully.',
      };
    } catch (e, stackTrace) {
      log('❌ SMS model update failed: $e');

      log('❌ Stack trace: $stackTrace');

      // Remove incomplete temporary download.
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}

      return {
        'success': false,
        'modelVersion': modelVersion,
        'message': 'SMS detection model update failed.',
        'error': e.toString(),
      };
    }
  }

  Future<int> getInstalledModelVersion() async {
    final prefs = await SharedPreferences.getInstance();

    // TEMPORARY RESET: return to the original bundled SMS model.
    await prefs.remove(_activeModelPathKey);
    await prefs.setInt(_smsModelVersionKey, defaultSmsModelVersion);

    return defaultSmsModelVersion;
  }

  // ============================================================
  // TEXT PROCESSING
  // ============================================================

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

  // ============================================================
  // KEYWORD / PATTERN DETECTION
  // ============================================================

  int _keywordScore(String message) {
    final text = message.toLowerCase();
    int score = 0;

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

    final hasOtp = text.contains('otp') || text.contains('one-time password');

    final hasShareRequest =
        text.contains('share your otp') ||
        text.contains('send your otp') ||
        text.contains('give your otp') ||
        text.contains('provide your otp') ||
        text.contains('tell me your otp');

    final hasOtpInputRequest =
        text.contains('enter your otp') ||
        text.contains('input your otp') ||
        text.contains('submit your otp');

    final hasSuspiciousOtpContext =
        text.contains('verify') ||
        text.contains('confirm') ||
        text.contains('validate') ||
        text.contains('click') ||
        text.contains('tap') ||
        text.contains('link') ||
        text.contains('urgent') ||
        text.contains('immediately') ||
        text.contains('account') ||
        text.contains('suspended') ||
        text.contains('restricted') ||
        text.contains('locked');

    if (hasOtp) {
      if (hasShareRequest) {
        score += 3;
      }

      if (hasOtpInputRequest) {
        score += 2;
      }

      if (hasSuspiciousOtpContext) {
        score += 2;
      }
    }

    if (text.contains('do not share') &&
        (hasShareRequest || hasOtpInputRequest)) {
      score += 1;
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

    if (text.contains('verify') && text.contains('account')) {
      score += 2;
    }

    if (text.contains('account') && text.contains('suspended')) {
      score += 2;
    }

    if (text.contains('account') && text.contains('locked')) {
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

  // ============================================================
  // PREDICTION
  // ============================================================

  Future<SmsDetectionResult> predict(String message) async {
    await loadModel();

    final sequence = _textToSequence(message);

    final input = [sequence];

    final output = List.generate(1, (_) => List.filled(1, 0.0));

    _interpreter!.run(input, output);

    final probability = (output[0][0] as num).toDouble();

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

  // ============================================================
  // CLEANUP
  // ============================================================

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
