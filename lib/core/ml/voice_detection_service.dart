import 'dart:developer';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_litert/flutter_litert.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_mfcc_extractor.dart';

class VoiceDetectionService {
  Interpreter? _interpreter;
  FlexDelegate? _flexDelegate;
  final VoiceMfccExtractor _extractor = VoiceMfccExtractor();

  // ── Thresholds ────────────────────────────────────────────────────────────
  // fakeScore is sigmoid output:
  // 0.0 = real/human
  // 1.0 = deepfake
  static const double _deepfakeThreshold = 0.65;
  static const double _humanThreshold = 0.45;

  static const double _silenceRmsThreshold = 0.01;

  static const bool _debugMode = true;

  // ── Model versions ───────────────────────────────────────────────────────
  //
  // V4 is the bundled/default model.
  //
  // If a newer model has been downloaded through the updater, the downloaded
  // model will be loaded instead.
  //
  // This allows:
  //
  //   Fresh install → V4 bundled model
  //   Updated model → V5 local downloaded model
  //
  static const int _defaultModelVersion = 4;
  static const String _defaultModelAsset =
      'assets/models/voice_model_v4.tflite';

  // ─────────────────────────────────────────────────────────────────────────
  // MODEL
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> loadModel() async {
    if (_interpreter != null) return;

    final prefs = await SharedPreferences.getInstance();

    final installedVersion =
        prefs.getInt('voice_model_version') ?? _defaultModelVersion;

    final appDirectory = await getApplicationDocumentsDirectory();

    final downloadedModelPath =
        '${appDirectory.path}/voice_model_v$installedVersion.tflite';

    String modelSource;
    bool usingDownloadedModel = false;

    /*
     * If a downloaded model exists locally, use it.
     *
     * This is what allows the Voice Model Update feature to replace the
     * bundled V4 model with a downloaded V5 model without changing the
     * actual voice-analysis pipeline.
     */
    if (installedVersion > _defaultModelVersion &&
        await File(downloadedModelPath).exists()) {
      modelSource = downloadedModelPath;
      usingDownloadedModel = true;
    } else {
      /*
       * No newer downloaded model exists.
       *
       * Use the bundled V4 model as the fallback.
       */
      modelSource = _defaultModelAsset;
    }

    if (_debugMode) {
      log('════════════════════════════════════');
      log('🎤 Voice Model Loading');
      log('📌 Installed version: v$installedVersion');
      log('📦 Model source: $modelSource');
      log(
        '☁️ Downloaded model: '
        '${usingDownloadedModel ? "YES" : "NO"}',
      );
      log('════════════════════════════════════');
    }

    _flexDelegate = await FlexDelegate.create();

    final options = InterpreterOptions();
    options.addDelegate(_flexDelegate!);

    if (usingDownloadedModel) {
      _interpreter = Interpreter.fromFile(File(modelSource), options: options);
    } else {
      _interpreter = await Interpreter.fromAsset(
        _defaultModelAsset,
        options: options,
      );
    }

    if (_debugMode) {
      log('✅ Voice v$installedVersion model loaded successfully.');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VOICE MODEL UPDATE
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> installDownloadedModel({
    required String modelPath,
    required int modelVersion,
  }) async {
    try {
      final sourceFile = File(modelPath);

      if (!await sourceFile.exists()) {
        log('❌ Voice model update failed: source file does not exist.');
        return false;
      }

      if (modelVersion <= _defaultModelVersion) {
        log(
          '⚠️ Voice model v$modelVersion is not newer than '
          'bundled v$_defaultModelVersion.',
        );
        return false;
      }

      final appDirectory = await getApplicationDocumentsDirectory();

      final destinationPath =
          '${appDirectory.path}/voice_model_v$modelVersion.tflite';

      final destinationFile = File(destinationPath);

      /*
       * Close the currently loaded interpreter before replacing the model.
       */
      close();

      /*
       * Copy the downloaded model into the app's private storage.
       */
      await sourceFile.copy(destinationPath);

      /*
       * Verify that the copied file actually exists and is not empty.
       */
      if (!await destinationFile.exists()) {
        log('❌ Voice model destination file was not created.');
        return false;
      }

      final fileSize = await destinationFile.length();

      if (fileSize <= 0) {
        log('❌ Voice model file is empty.');
        return false;
      }

      /*
       * Save the installed model version.
       */
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt('voice_model_version', modelVersion);

      /*
       * Load the new model immediately so the current app session can use it.
       */
      await loadModel();

      log('✅ Voice model v$modelVersion installed successfully.');

      return true;
    } catch (e, stackTrace) {
      log('❌ VOICE MODEL INSTALL ERROR: $e');
      log('❌ VOICE MODEL INSTALL STACK TRACE: $stackTrace');

      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOWNLOAD + INSTALL VOICE MODEL UPDATE
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> downloadAndInstallModel({
    required String storagePath,
    required int modelVersion,
  }) async {
    String? temporaryPath;

    try {
      log('☁️ Starting voice model download...');
      log('📦 Storage path: $storagePath');
      log('🎤 Target version: v$modelVersion');

      if (modelVersion <= _defaultModelVersion) {
        log(
          '⚠️ Voice model v$modelVersion is not newer than '
          'bundled v$_defaultModelVersion.',
        );
        return false;
      }

      final tempDirectory = await getTemporaryDirectory();

      temporaryPath = '${tempDirectory.path}/voice_model_v$modelVersion.tflite';

      final temporaryFile = File(temporaryPath);

      /*
       * Remove an old temporary copy if one exists.
       */
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }

      /*
       * Get the Firebase Storage reference.
       */
      final storageReference = FirebaseStorage.instance.ref().child(
        storagePath,
      );

      log('☁️ Downloading voice model from Firebase Storage...');

      /*
       * Download the model directly into the app's temporary storage.
       */
      await storageReference.writeToFile(temporaryFile);

      /*
       * Verify that the downloaded file exists and is not empty.
       */
      if (!await temporaryFile.exists()) {
        log('❌ Downloaded voice model file does not exist.');
        return false;
      }

      final downloadedSize = await temporaryFile.length();

      if (downloadedSize <= 0) {
        log('❌ Downloaded voice model file is empty.');
        return false;
      }

      log(
        '✅ Voice model download successful. '
        'Size: $downloadedSize bytes',
      );

      /*
       * Install the downloaded model into the app's private storage.
       */
      final installed = await installDownloadedModel(
        modelPath: temporaryPath,
        modelVersion: modelVersion,
      );

      if (!installed) {
        log('❌ Voice model installation failed.');
        return false;
      }

      log('✅ Voice model v$modelVersion downloaded and installed.');

      return true;
    } catch (e, stackTrace) {
      log('❌ VOICE MODEL DOWNLOAD ERROR: $e');
      log('❌ VOICE MODEL DOWNLOAD STACK TRACE: $stackTrace');

      return false;
    } finally {
      /*
       * Delete the temporary Firebase download.
       *
       * The installed copy is already stored separately inside
       * the application's private documents directory.
       */
      if (temporaryPath != null) {
        await _deleteFile(temporaryPath);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN WAV ANALYSIS
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> analyzeWavFile(String wavPath) async {
    try {
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

      // v4/v5 model input:
      // [batch, MFCC, timeFrames, channels]
      // [1, 40, 157, 2]
      final input = features.reshape([1, 40, 157, 2]);

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
          'action': 'Alert Shown',
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
    } catch (e, stackTrace) {
      log('❌ VOICE ANALYSIS ERROR: $e');
      log('❌ VOICE ANALYSIS STACK TRACE: $stackTrace');

      return {
        'label': 'Voice Detection Error',
        'result': -1,
        'confidence': 0.0,
        'fakeScore': 0.0,
        'safe': false,
        'action': 'Voice analysis failed',
        'error': e.toString(),
      };
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UPLOADED AUDIO ANALYSIS
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> analyzeAudioFile(
    String inputPath, {
    String? fileName,
  }) async {
    String? convertedPath;

    try {
      log(
        '📁 Starting uploaded audio analysis: '
        '${fileName ?? inputPath}',
      );

      final inputFile = File(inputPath);

      if (!await inputFile.exists()) {
        throw Exception('Selected audio file does not exist.');
      }

      final tempDirectory = await getTemporaryDirectory();

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      convertedPath =
          '${tempDirectory.path}/pare_voice_converted_$timestamp.wav';

      log('🎵 Converting uploaded audio...');
      log('📥 Input: $inputPath');
      log('📤 Output: $convertedPath');

      /*
       * Convert ANY supported input audio into the exact format required
       * by the voice model preprocessing pipeline.
       *
       * -ar 16000 = 16 kHz sample rate
       * -ac 1     = mono
       * -c:a pcm_s16le = 16-bit PCM WAV
       */
      final command =
          '-y '
          '-i "${_escapeFFmpegPath(inputPath)}" '
          '-vn '
          '-ac 1 '
          '-ar 16000 '
          '-c:a pcm_s16le '
          '"${_escapeFFmpegPath(convertedPath)}"';

      log('🎬 FFmpeg command started.');

      final session = await FFmpegKit.execute(command);

      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();

        log('❌ FFmpeg conversion failed.');
        log('❌ Return code: $returnCode');
        log('❌ FFmpeg output: $output');

        throw Exception('Unable to convert the selected audio file.');
      }

      final convertedFile = File(convertedPath);

      if (!await convertedFile.exists()) {
        throw Exception(
          'Audio conversion completed but the converted '
          'file was not created.',
        );
      }

      final convertedSize = await convertedFile.length();

      if (convertedSize <= 44) {
        throw Exception('Converted audio file is empty or invalid.');
      }

      log('✅ Audio conversion successful.');
      log('📦 Converted size: $convertedSize bytes');

      /*
       * Use the SAME analysis pipeline as analyzeWavFile().
       *
       * Therefore uploaded audio automatically uses whichever
       * voice model is currently installed.
       */
      final result = await analyzeWavFile(convertedPath);

      /*
       * analyzeWavFile() already deletes the converted WAV.
       */
      convertedPath = null;

      /*
       * Preserve uploaded-file information.
       */
      result['callerName'] = fileName ?? inputFile.uri.pathSegments.last;

      result['callerNumber'] = 'Uploaded File';

      result['type'] = 'Voice Upload';

      log(
        '📁 Upload Analysis Result: '
        '${result['label']}',
      );

      log(
        '📊 Confidence: '
        '${result['confidence']}',
      );

      return result;
    } catch (e, stackTrace) {
      log('❌ UPLOADED AUDIO ANALYSIS ERROR: $e');

      log(
        '❌ UPLOADED AUDIO ANALYSIS STACK TRACE: '
        '$stackTrace',
      );

      return {
        'label': 'Voice Detection Error',
        'result': -1,
        'confidence': 0.0,
        'fakeScore': 0.0,
        'safe': false,
        'action': 'Voice analysis failed',
        'error': e.toString(),
        'callerName': fileName ?? 'Uploaded Audio',
        'callerNumber': 'Uploaded File',
        'type': 'Voice Upload',
      };
    } finally {
      /*
       * Clean up converted temporary WAV if something failed before
       * analyzeWavFile() could delete it.
       */
      if (convertedPath != null) {
        await _deleteFile(convertedPath);
      }

      /*
       * Also clean up the original picker cache file.
       */
      await _deleteFile(inputPath);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FFmpeg PATH ESCAPING
  // ─────────────────────────────────────────────────────────────────────────

  String _escapeFFmpegPath(String path) {
    return path.replaceAll('"', r'\"');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SILENCE DETECTION
  // ─────────────────────────────────────────────────────────────────────────

  bool _isSilence(List<double> features) {
    double sumSq = 0;

    for (final v in features) {
      sumSq += v * v;
    }

    return (sumSq / features.length) < _silenceRmsThreshold;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILE CLEANUP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);

      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Temporary-file cleanup failure should not crash the app.
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLOSE MODEL
  // ─────────────────────────────────────────────────────────────────────────

  void close() {
    _interpreter?.close();
    _interpreter = null;

    _flexDelegate?.delete();
    _flexDelegate = null;
  }
}
