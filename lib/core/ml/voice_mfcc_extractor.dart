import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class VoiceMfccExtractor {
  static const int sampleRate = 16000;
  static const int nMfcc = 40;
  static const int timeFrames = 157;
  static const int fftSize = 2048;
  static const int hopLength = 512;
  static const int nMels = 128;
  static const double fMin = 0.0;
  static const double fMax = 8000.0;

  // Exact number of samples needed for 157 frames:
  // (timeFrames - 1) * hopLength + fftSize = 156 * 512 + 2048 = 82_432
  static const int targetSamples = 82432;

  List<Float32List>? _melFilterbank;

  Future<Float32List> extractFromWav(String path) async {
    final bytes = await File(path).readAsBytes();
    final headerOffset = _getWavDataOffset(bytes);
    final pcmBytes = bytes.sublist(headerOffset);

    // ── 1. Decode PCM → float32, pad/trim to exactly targetSamples ──
    final byteData = ByteData.sublistView(Uint8List.fromList(pcmBytes));
    final sampleCount = byteData.lengthInBytes ~/ 2;
    final samples = Float32List(targetSamples); // zero-padded by default

    final readCount = min(sampleCount, targetSamples);
    for (int i = 0; i < readCount; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }

    // ── 2. Build filterbank once ──
    _melFilterbank ??= _buildMelFilterbank();

    // ── 3. Compute MFCCs frame by frame ──
    // Layout: features[mfcc_index * timeFrames + time_index]  →  shape (40, 157)
    final features = Float32List(nMfcc * timeFrames);

    for (int t = 0; t < timeFrames; t++) {
      final start = t * hopLength;
      final frame = Float32List(fftSize);

      for (int i = 0; i < fftSize; i++) {
        final idx = start + i;
        frame[i] = idx < samples.length ? samples[idx] : 0.0;
      }

      _applyHannWindow(frame);

      final power = _powerSpectrum(frame);
      final logMel = _applyMelFilterbank(power, _melFilterbank!);
      final mfccs = _dct(logMel); // length = nMfcc

      for (int m = 0; m < nMfcc; m++) {
        features[m * timeFrames + t] = mfccs[m];
      }
    }

    // ── 4. Global mean/std normalisation — matches predict.py exactly ──
    //   mfcc = (mfcc - np.mean(mfcc)) / (np.std(mfcc) + 1e-6)
    return _normalize(features);
  }

  // ── WAV header parser ────────────────────────────────────────────────────

  int _getWavDataOffset(Uint8List bytes) {
    for (int i = 12; i < bytes.length - 8; i++) {
      if (bytes[i] == 0x64 && // d
          bytes[i + 1] == 0x61 && // a
          bytes[i + 2] == 0x74 && // t
          bytes[i + 3] == 0x61) {
        // a
        return i + 8;
      }
    }
    return 44; // fallback
  }

  // ── Signal processing ────────────────────────────────────────────────────

  void _applyHannWindow(Float32List frame) {
    final n = frame.length;
    for (int i = 0; i < n; i++) {
      frame[i] *= 0.5 * (1.0 - cos(2.0 * pi * i / (n - 1)));
    }
  }

  Float32List _powerSpectrum(Float32List frame) {
    final real = Float64List(fftSize);
    final imag = Float64List(fftSize);
    for (int i = 0; i < fftSize; i++) {
      real[i] = frame[i];
    }

    _fft(real, imag);

    final halfN = fftSize ~/ 2 + 1;
    final power = Float32List(halfN);
    for (int i = 0; i < halfN; i++) {
      power[i] = (real[i] * real[i] + imag[i] * imag[i]).toDouble();
    }
    return power;
  }

  void _fft(Float64List real, Float64List imag) {
    final n = real.length;

    // Bit-reversal
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var t = real[i];
        real[i] = real[j];
        real[j] = t;
        t = imag[i];
        imag[i] = imag[j];
        imag[j] = t;
      }
    }

    // Butterfly
    for (int len = 2; len <= n; len <<= 1) {
      final ang = -2.0 * pi / len;
      final wRe = cos(ang);
      final wIm = sin(ang);
      for (int i = 0; i < n; i += len) {
        double cRe = 1.0, cIm = 0.0;
        for (int k = 0; k < len ~/ 2; k++) {
          final uRe = real[i + k];
          final uIm = imag[i + k];
          final vRe =
              real[i + k + len ~/ 2] * cRe - imag[i + k + len ~/ 2] * cIm;
          final vIm =
              real[i + k + len ~/ 2] * cIm + imag[i + k + len ~/ 2] * cRe;
          real[i + k] = uRe + vRe;
          imag[i + k] = uIm + vIm;
          real[i + k + len ~/ 2] = uRe - vRe;
          imag[i + k + len ~/ 2] = uIm - vIm;
          final nCRe = cRe * wRe - cIm * wIm;
          cIm = cRe * wIm + cIm * wRe;
          cRe = nCRe;
        }
      }
    }
  }

  // ── Mel filterbank ───────────────────────────────────────────────────────
  // Matches librosa.filters.mel() exactly:
  //   - mel points spaced linearly in mel scale
  //   - bin indices computed via hz-to-bin formula (not indexWhere)
  //   - triangular filters normalised by filter width (norm=None by default)

  List<Float32List> _buildMelFilterbank() {
    final halfN = fftSize ~/ 2 + 1;
    final melMin = _hzToMel(fMin);
    final melMax = _hzToMel(fMax);

    // nMels + 2 equally spaced mel points
    final melPts = List<double>.generate(
      nMels + 2,
      (i) => melMin + i * (melMax - melMin) / (nMels + 1),
    );

    // Convert to Hz then to FFT bin index (fractional)
    final binPts = melPts.map((m) {
      final hz = _melToHz(m);
      return hz * fftSize / sampleRate; // fractional bin
    }).toList();

    final fb = List<Float32List>.generate(nMels, (_) => Float32List(halfN));

    for (int m = 1; m <= nMels; m++) {
      final left = binPts[m - 1];
      final center = binPts[m];
      final right = binPts[m + 1];

      for (int k = 0; k < halfN; k++) {
        final kd = k.toDouble();
        if (kd > left && kd < center) {
          fb[m - 1][k] = (kd - left) / (center - left);
        } else if (kd >= center && kd < right) {
          fb[m - 1][k] = (right - kd) / (right - center);
        }
      }
    }

    return fb;
  }

  Float32List _applyMelFilterbank(Float32List power, List<Float32List> fb) {
    final logMel = Float32List(nMels);
    for (int m = 0; m < nMels; m++) {
      double energy = 0.0;
      for (int k = 0; k < power.length; k++) {
        energy += fb[m][k] * power[k];
      }
      logMel[m] = log(energy + 1e-6);
    }
    return logMel;
  }

  // ── DCT-II with ortho normalisation — matches librosa/scipy exactly ──────
  // scipy.fft.dct(x, type=2, norm='ortho') scaling:
  //   k=0 : x[k] *= sqrt(1 / (4N))   → factor = sqrt(1/(4*N))
  //   k>0 : x[k] *= sqrt(1 / (2N))   → factor = sqrt(1/(2*N))
  List<double> _dct(Float32List input) {
    final n = input.length; // nMels = 128
    final out = List<double>.filled(nMfcc, 0.0);

    for (int k = 0; k < nMfcc; k++) {
      double sum = 0.0;
      for (int i = 0; i < n; i++) {
        sum += input[i] * cos(pi * k * (2 * i + 1) / (2 * n));
      }
      // Orthonormal scaling
      out[k] = k == 0
          ? sum * sqrt(1.0 / (4.0 * n))
          : sum * sqrt(1.0 / (2.0 * n));
    }
    return out;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  double _hzToMel(double hz) => 2595.0 * log(1.0 + hz / 700.0) / ln10;
  double _melToHz(double mel) => 700.0 * (pow(10.0, mel / 2595.0) - 1.0);

  Float32List _normalize(Float32List data) {
    double sum = 0.0;
    for (final v in data) {
      sum += v;
    }
    final mean = sum / data.length;

    double variance = 0.0;
    for (final v in data) {
      variance += (v - mean) * (v - mean);
    }
    final std = sqrt(variance / data.length) + 1e-6;

    final out = Float32List(data.length);
    for (int i = 0; i < data.length; i++) {
      out[i] = (data[i] - mean) / std;
    }
    return out;
  }
}
