import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class VoiceMfccExtractor {
  static const int sampleRate = 16000;
  static const int targetSamples = 80000; // 5 seconds

  static const int nMfcc = 40;
  static const int timeFrames = 157;

  // ── Must exactly match librosa.feature.mfcc() defaults ──
  // librosa default: n_fft=2048, hop_length=512, n_mels=128
  // No pre-emphasis (librosa does NOT apply it by default)
  static const int fftSize = 2048;
  static const int hopLength = 512;
  static const int nMels = 128;
  static const double fMin = 0.0;
  static const double fMax = 8000.0; // sr / 2

  // Cache the filterbank so it is only built once per instance
  List<Float32List>? _melFilterbank;

  Future<Float32List> extractFromWav(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();

    final headerOffset = _getWavDataOffset(bytes);
    final pcmBytes = bytes.sublist(headerOffset);

    final samples = Float32List(targetSamples);
    final byteData = ByteData.sublistView(Uint8List.fromList(pcmBytes));
    final sampleCount = min(byteData.lengthInBytes ~/ 2, targetSamples);

    for (int i = 0; i < sampleCount; i++) {
      final intSample = byteData.getInt16(i * 2, Endian.little);
      samples[i] = intSample / 32768.0;
    }

    _melFilterbank ??= _buildMelFilterbank();
    final melFilterbank = _melFilterbank!;

    final features = Float32List(nMfcc * timeFrames);

    for (int t = 0; t < timeFrames; t++) {
      final start = t * hopLength;
      final frame = Float32List(fftSize);

      for (int i = 0; i < fftSize; i++) {
        final idx = start + i;
        frame[i] = (idx < samples.length) ? samples[idx] : 0.0;
      }

      // Hann window — librosa default
      _applyHannWindow(frame);

      final powerSpectrum = _powerSpectrum(frame);
      final logMelEnergies = _applyMelFilterbank(powerSpectrum, melFilterbank);
      final mfccs = _dct(logMelEnergies);

      for (int m = 0; m < nMfcc; m++) {
        features[(m * timeFrames) + t] = mfccs[m];
      }
    }

    // Global mean/std normalization matching predict.py:
    // mfcc = (mfcc - np.mean(mfcc)) / (np.std(mfcc) + 1e-6)
    return _normalize(features);
  }

  /// Scan WAV bytes for the 'data' chunk instead of hardcoding offset 44
  int _getWavDataOffset(Uint8List bytes) {
    for (int i = 12; i < bytes.length - 8; i++) {
      if (bytes[i] == 0x64 && // 'd'
          bytes[i + 1] == 0x61 && // 'a'
          bytes[i + 2] == 0x74 && // 't'
          bytes[i + 3] == 0x61) {
        // 'a'
        return i + 8;
      }
    }
    return 44; // fallback
  }

  /// Hann window — librosa uses this by default
  void _applyHannWindow(Float32List frame) {
    final n = frame.length;
    for (int i = 0; i < n; i++) {
      final w = 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1)));
      frame[i] *= w;
    }
  }

  /// Power spectrum |FFT(frame)|^2 for bins 0..fftSize/2
  Float32List _powerSpectrum(Float32List frame) {
    final n = fftSize;
    final real = Float64List(n);
    final imag = Float64List(n);

    for (int i = 0; i < n; i++) {
      real[i] = frame[i];
    }

    _fft(real, imag);

    final halfN = n ~/ 2 + 1;
    final power = Float32List(halfN);
    for (int i = 0; i < halfN; i++) {
      power[i] = (real[i] * real[i] + imag[i] * imag[i]).toDouble();
    }
    return power;
  }

  /// Cooley-Tukey radix-2 in-place FFT
  void _fft(Float64List real, Float64List imag) {
    final n = real.length;

    // Bit-reversal permutation
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = real[i];
        real[i] = real[j];
        real[j] = tr;
        final ti = imag[i];
        imag[i] = imag[j];
        imag[j] = ti;
      }
    }

    // Butterfly passes
    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2.0 * pi / len;
      final wRe = cos(ang);
      final wIm = sin(ang);
      for (int i = 0; i < n; i += len) {
        double curRe = 1.0;
        double curIm = 0.0;
        for (int k = 0; k < len ~/ 2; k++) {
          final uRe = real[i + k];
          final uIm = imag[i + k];
          final vRe =
              real[i + k + len ~/ 2] * curRe - imag[i + k + len ~/ 2] * curIm;
          final vIm =
              real[i + k + len ~/ 2] * curIm + imag[i + k + len ~/ 2] * curRe;
          real[i + k] = uRe + vRe;
          imag[i + k] = uIm + vIm;
          real[i + k + len ~/ 2] = uRe - vRe;
          imag[i + k + len ~/ 2] = uIm - vIm;
          final newCurRe = curRe * wRe - curIm * wIm;
          curIm = curRe * wIm + curIm * wRe;
          curRe = newCurRe;
        }
      }
    }
  }

  /// Triangular mel filterbank [nMels x (fftSize/2+1)]
  List<Float32List> _buildMelFilterbank() {
    final halfN = fftSize ~/ 2 + 1;
    final melMin = _hzToMel(fMin);
    final melMax = _hzToMel(fMax);

    final melPoints = List<double>.generate(
      nMels + 2,
      (i) => melMin + i * (melMax - melMin) / (nMels + 1),
    );

    final binFreqs = List<double>.generate(
      halfN,
      (i) => i.toDouble() * sampleRate / fftSize,
    );

    final binIndices = melPoints.map((m) {
      final hz = _melToHz(m);
      final idx = binFreqs.indexWhere((f) => f >= hz);
      return (idx < 0 ? halfN - 1 : idx).toDouble();
    }).toList();

    final filterbank = List<Float32List>.generate(
      nMels,
      (_) => Float32List(halfN),
    );

    for (int m = 1; m <= nMels; m++) {
      final left = binIndices[m - 1];
      final center = binIndices[m];
      final right = binIndices[m + 1];

      for (int k = 0; k < halfN; k++) {
        final kd = k.toDouble();
        if (kd >= left && kd <= center && center != left) {
          filterbank[m - 1][k] = (kd - left) / (center - left);
        } else if (kd >= center && kd <= right && right != center) {
          filterbank[m - 1][k] = (right - kd) / (right - center);
        }
      }
    }

    return filterbank;
  }

  /// Apply mel filterbank to power spectrum and return log mel energies
  Float32List _applyMelFilterbank(
    Float32List power,
    List<Float32List> filterbank,
  ) {
    final logMel = Float32List(nMels);
    for (int m = 0; m < nMels; m++) {
      double energy = 0.0;
      for (int k = 0; k < power.length; k++) {
        energy += filterbank[m][k] * power[k];
      }
      logMel[m] = log(energy + 1e-6);
    }
    return logMel;
  }

  /// Type-II DCT — matches scipy/librosa DCT used internally
  List<double> _dct(Float32List input) {
    final n = input.length;
    final out = List<double>.filled(nMfcc, 0.0);
    for (int k = 0; k < nMfcc; k++) {
      double sum = 0.0;
      for (int i = 0; i < n; i++) {
        sum += input[i] * cos(pi * k * (2 * i + 1) / (2 * n));
      }
      out[k] = sum;
    }
    return out;
  }

  double _hzToMel(double hz) => 2595.0 * log(1.0 + hz / 700.0) / ln10;
  double _melToHz(double mel) => 700.0 * (pow(10.0, mel / 2595.0) - 1.0);

  /// Global normalization matching predict.py exactly:
  /// mfcc = (mfcc - np.mean(mfcc)) / (np.std(mfcc) + 1e-6)
  Float32List _normalize(Float32List data) {
    double sum = 0.0;
    for (final value in data) {
      sum += value;
    }
    final mean = sum / data.length;

    double variance = 0.0;
    for (final value in data) {
      variance += pow(value - mean, 2);
    }
    final std = sqrt(variance / data.length) + 1e-6;

    final normalized = Float32List(data.length);
    for (int i = 0; i < data.length; i++) {
      normalized[i] = (data[i] - mean) / std;
    }
    return normalized;
  }
}
