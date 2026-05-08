import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecordingService {
  AudioRecorder? _recorder;

  AudioRecorder get _rec {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  // durationSeconds bumped to 6 so we always capture > 82,432 samples
  // (82,432 samples / 16,000 Hz = 5.152 s — 6 s gives comfortable headroom)
  Future<String?> recordTenSeconds({
    int durationSeconds = 6,
    bool demoMode = false,
  }) async {
    final hasPermission = await _rec.hasPermission();

    if (!hasPermission) {
      debugPrint('🎙️ Microphone permission denied');
      return null;
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/pare_voice_sample.wav';

    final existing = File(filePath);
    if (await existing.exists()) await existing.delete();

    await _rec.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(
          audioSource: demoMode
              ? AndroidAudioSource.mic
              : AndroidAudioSource.voiceCommunication,
        ),
      ),
      path: filePath,
    );

    debugPrint(
      demoMode
          ? '🎤 Demo microphone recording started (${durationSeconds}s)...'
          : '📞 Call audio recording started (${durationSeconds}s)...',
    );

    await Future.delayed(Duration(seconds: durationSeconds));

    final savedPath = await _rec.stop();

    if (savedPath == null) {
      debugPrint('🎙️ Recorder returned null path');
      return null;
    }

    final file = File(savedPath);
    if (!await file.exists()) {
      debugPrint('🎙️ Recorded file does not exist');
      return null;
    }

    final fileSize = await file.length();
    debugPrint('🎙️ Recorded file size: $fileSize bytes');

    if (fileSize < 1000) {
      debugPrint('🎙️ Recording file too small, discarding.');
      await file.delete();
      return null;
    }

    final rms = await _computeRms(savedPath);
    debugPrint('🎙️ Recorded RMS: $rms');

    if (rms < 0.0003) {
      debugPrint('🎙️ Recording appears silent (RMS=$rms), discarding.');
      await file.delete();
      return null;
    }

    return savedPath;
  }

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
      if (pcm.isEmpty) return 0.0;

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
      return 1.0;
    }
  }

  Future<void> dispose() async {
    await _recorder?.dispose();
    _recorder = null;
  }
}
