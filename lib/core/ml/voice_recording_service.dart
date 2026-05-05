import 'dart:io';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';

class VoiceRecordingService {
  AudioRecorder? _recorder;

  AudioRecorder get _rec {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  /// Records up to [durationSeconds] seconds of call audio.
  /// Returns null only if permission is denied.
  /// Returns a WAV path even for low-energy recordings — the model decides.
  Future<String?> recordTenSeconds({int durationSeconds = 10}) async {
    final hasPermission = await _rec.hasPermission();
    if (!hasPermission) {
      debugPrint('🎙️ Microphone permission denied');
      return null;
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/pare_voice_sample.wav';

    // Delete any leftover file from a previous call
    final existing = File(filePath);
    if (await existing.exists()) await existing.delete();

    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        // VOICE_COMMUNICATION (Android source 7) applies echo cancellation
        // and noise suppression tuned for phone calls, and — crucially —
        // it can capture audio even when the telephony stack holds focus.
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceCommunication,
        ),
      ),
      path: filePath,
    );

    debugPrint('🎙️ Recording started (${durationSeconds}s)…');
    await Future.delayed(Duration(seconds: durationSeconds));

    final savedPath = await _rec.stop();
    if (savedPath == null) {
      debugPrint('🎙️ Recorder returned null path');
      return null;
    }

    // Log RMS so we can tune the threshold without guessing
    final rms = await _computeRms(savedPath);
    debugPrint('🎙️ Recorded RMS: $rms');

    // Very low bar — only reject truly empty/corrupt files.
    // The model handles the "low voice / ambient noise" case better than VAD.
    if (rms < 0.0005) {
      debugPrint('🎙️ Recording appears silent (RMS=$rms), discarding.');
      final f = File(savedPath);
      if (await f.exists()) await f.delete();
      return null;
    }

    return savedPath;
  }

  /// Computes RMS energy of the PCM data in a WAV file.
  Future<double> _computeRms(String path) async {
    try {
      final bytes = await File(path).readAsBytes();

      int dataOffset = 44;
      for (int i = 12; i < bytes.length - 8; i++) {
        if (bytes[i] == 0x64 &&
            bytes[i + 1] == 0x61 &&
            bytes[i + 2] == 0x74 &&
            bytes[i + 3] == 0x61) {
          dataOffset = i + 8;
          break;
        }
      }

      final pcm = bytes.sublist(dataOffset);
      final byteData = ByteData.sublistView(Uint8List.fromList(pcm));
      final sampleCount = byteData.lengthInBytes ~/ 2;
      if (sampleCount == 0) return 0.0;

      double sumSq = 0;
      for (int i = 0; i < sampleCount; i++) {
        final s = byteData.getInt16(i * 2, Endian.little) / 32768.0;
        sumSq += s * s;
      }

      return sqrt(sumSq / sampleCount);
    } catch (e) {
      debugPrint('🎙️ RMS computation error: $e');
      return 1.0; // let the model decide on error
    }
  }

  Future<void> dispose() async {
    await _recorder?.dispose();
    _recorder = null;
  }
}
