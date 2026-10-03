import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class VoiceMfccExtractor {
  static const int sampleRate = 16000;
  static const int targetSamples = 80000; // 5 seconds
  static const int nMfcc = 40;
  static const int nMels = 40;

  // IMPORTANT:
  // librosa.feature.mfcc() uses 128 Mel bands internally
  // when n_mels is not explicitly specified.
  static const int mfccMels = 128;

  static const int fftSize = 2048;
  static const int hopLength = 512;
  static const int targetFrames = 157;

  List<double>? _hannWindow;
  List<List<double>>? _melFilterbank40;
  List<List<double>>? _melFilterbank128;
  List<List<double>>? _dctMatrix;

  // ============================================================
  // MAIN FEATURE EXTRACTION
  // ============================================================

  Future<Float32List> extractFromWav(String path) async {
    final wav = await _readWav(path);

    List<double> audio = wav.samples;
    final int originalSampleRate = wav.sampleRate;

    // ------------------------------------------------------------
    // Resample to 16 kHz if necessary
    // ------------------------------------------------------------

    if (originalSampleRate != sampleRate) {
      audio = _resampleLinear(audio, originalSampleRate, sampleRate);
    }

    // ------------------------------------------------------------
    // Make audio exactly 5 seconds / 80,000 samples
    // ------------------------------------------------------------

    if (audio.length > targetSamples) {
      audio = audio.sublist(0, targetSamples);
    } else if (audio.length < targetSamples) {
      final padded = List<double>.filled(targetSamples, 0.0);

      for (int i = 0; i < audio.length; i++) {
        padded[i] = audio[i];
      }

      audio = padded;
    }

    // ------------------------------------------------------------
    // Match librosa's centered STFT behavior
    //
    // librosa center=True with n_fft=2048 effectively pads
    // 1024 samples on both sides.
    // ------------------------------------------------------------

    final List<double> centeredAudio = _centerPad(audio);

    // ------------------------------------------------------------
    // Initialize cached components
    // ------------------------------------------------------------

    _hannWindow ??= _buildHannWindow();

    _melFilterbank40 ??= _buildMelFilterbank(nMels);

    _melFilterbank128 ??= _buildMelFilterbank(mfccMels);

    _dctMatrix ??= _buildDctMatrix(nMfcc, mfccMels);

    // ------------------------------------------------------------
    // MFCC
    //
    // This must use 128 Mel bands because the Python code uses:
    //
    // librosa.feature.mfcc(
    //     y=audio,
    //     sr=sr,
    //     n_mfcc=40
    // )
    //
    // librosa defaults to 128 Mel bands internally.
    // ------------------------------------------------------------

    final List<Float32List> mfcc = _extractMfcc(centeredAudio);

    // ------------------------------------------------------------
    // 40-band Log-Mel Spectrogram
    //
    // Python:
    //
    // librosa.feature.melspectrogram(
    //     y=audio,
    //     sr=sr,
    //     n_mels=40
    // )
    // ------------------------------------------------------------

    final List<Float32List> logMel = _extractLogMel(
      centeredAudio,
      _melFilterbank40!,
    );

    // ------------------------------------------------------------
    // Normalize exactly after feature extraction
    //
    // Python does:
    //
    // mfcc = (mfcc - mean) / (std + 1e-6)
    // mel  = (mel  - mean) / (std + 1e-6)
    // ------------------------------------------------------------

    _normalizeInPlace(mfcc);
    _normalizeInPlace(logMel);

    // ------------------------------------------------------------
    // Combine:
    //
    // [40 MFCC, 157 frames, 1]
    // +
    // [40 Log-Mel, 157 frames, 1]
    //
    // =
    // [40, 157, 2]
    // ------------------------------------------------------------

    final Float32List combined = Float32List(nMfcc * targetFrames * 2);

    int index = 0;

    for (int m = 0; m < nMfcc; m++) {
      for (int frame = 0; frame < targetFrames; frame++) {
        combined[index++] = mfcc[m][frame];
        combined[index++] = logMel[m][frame];
      }
    }

    return combined;
  }

  // ============================================================
  // MFCC EXTRACTION
  // ============================================================

  List<Float32List> _extractMfcc(List<double> samples) {
    final int nFft = fftSize;
    final int hop = hopLength;

    // With 80,000 samples + 1024 center padding:
    //
    // frameCount = 1 + floor((82048 - 2048) / 512)
    //            = 157
    //
    // This matches librosa's expected 157 frames.
    final int frameCount = ((samples.length - nFft) ~/ hop) + 1;

    final List<Float32List> mfcc = List.generate(
      nMfcc,
      (_) => Float32List(frameCount),
    );

    final List<List<double>> melFilterbank = _melFilterbank128 ??=
        _buildMelFilterbank(mfccMels);

    final List<List<double>> dct = _dctMatrix ??= _buildDctMatrix(
      nMfcc,
      mfccMels,
    );

    // ------------------------------------------------------------
    // First calculate the complete Mel spectrogram.
    //
    // This is important because librosa.power_to_db uses the
    // maximum value of the WHOLE spectrogram when ref=np.max.
    // ------------------------------------------------------------

    final List<List<double>> melPower = List.generate(
      mfccMels,
      (_) => List<double>.filled(frameCount, 0.0),
    );

    final Float64List window = Float64List(nFft);

    final Float64List real = Float64List(nFft);
    final Float64List imag = Float64List(nFft);

    for (int frame = 0; frame < frameCount; frame++) {
      final int start = frame * hop;

      // ----------------------------------------------------------
      // Apply Hann window
      // ----------------------------------------------------------

      for (int i = 0; i < nFft; i++) {
        final int sampleIndex = start + i;

        final double sample = sampleIndex < samples.length
            ? samples[sampleIndex]
            : 0.0;

        window[i] = sample * _hannWindow![i];
      }

      // ----------------------------------------------------------
      // Prepare FFT arrays
      // ----------------------------------------------------------

      for (int i = 0; i < nFft; i++) {
        real[i] = window[i];
        imag[i] = 0.0;
      }

      _fft(real, imag);

      // ----------------------------------------------------------
      // Power spectrum
      // ----------------------------------------------------------

      final int positiveBins = nFft ~/ 2 + 1;

      final Float64List power = Float64List(positiveBins);

      for (int k = 0; k < positiveBins; k++) {
        final double r = real[k];
        final double im = imag[k];

        power[k] = (r * r + im * im) / nFft;
      }

      // ----------------------------------------------------------
      // Apply 128-band Mel filterbank
      // ----------------------------------------------------------

      for (int mel = 0; mel < mfccMels; mel++) {
        double sum = 0.0;

        final List<double> filter = melFilterbank[mel];

        final int maxBin = min(positiveBins, filter.length);

        for (int k = 0; k < maxBin; k++) {
          final double weight = filter[k];

          if (weight != 0.0) {
            sum += power[k] * weight;
          }
        }

        melPower[mel][frame] = sum;
      }
    }

    // ------------------------------------------------------------
    // Find GLOBAL maximum.
    //
    // Python:
    // librosa.power_to_db(mel, ref=np.max)
    //
    // So the reference is the maximum of the entire Mel
    // spectrogram, NOT the maximum of each frame.
    // ------------------------------------------------------------

    double globalMax = 0.0;

    for (int mel = 0; mel < mfccMels; mel++) {
      for (int frame = 0; frame < frameCount; frame++) {
        if (melPower[mel][frame] > globalMax) {
          globalMax = melPower[mel][frame];
        }
      }
    }

    if (globalMax <= 0.0) {
      globalMax = 1e-10;
    }

    // ------------------------------------------------------------
    // Convert power to dB.
    //
    // librosa.power_to_db(..., ref=np.max)
    // default top_db = 80
    // ------------------------------------------------------------

    final double referenceDb = 10.0 * log(globalMax) / ln10;

    final double minimumDb = referenceDb - 80.0;

    for (int mel = 0; mel < mfccMels; mel++) {
      for (int frame = 0; frame < frameCount; frame++) {
        double value = melPower[mel][frame];

        if (value < 1e-10) {
          value = 1e-10;
        }

        double db = 10.0 * log(value) / ln10;

        if (db < minimumDb) {
          db = minimumDb;
        }

        melPower[mel][frame] = db;
      }
    }

    // ------------------------------------------------------------
    // DCT-II
    //
    // Convert 128 Mel coefficients -> 40 MFCC coefficients.
    // ------------------------------------------------------------

    for (int coefficient = 0; coefficient < nMfcc; coefficient++) {
      for (int frame = 0; frame < frameCount; frame++) {
        double sum = 0.0;

        for (int mel = 0; mel < mfccMels; mel++) {
          sum += dct[coefficient][mel] * melPower[mel][frame];
        }

        mfcc[coefficient][frame] = sum;
      }
    }

    return mfcc;
  }

  // ============================================================
  // LOG-MEL EXTRACTION
  // ============================================================

  List<Float32List> _extractLogMel(
    List<double> samples,
    List<List<double>> filterbank,
  ) {
    final int nFft = fftSize;
    final int hop = hopLength;

    final int frameCount = ((samples.length - nFft) ~/ hop) + 1;

    final List<Float32List> result = List.generate(
      nMels,
      (_) => Float32List(frameCount),
    );

    final Float64List window = Float64List(nFft);

    final Float64List real = Float64List(nFft);

    final Float64List imag = Float64List(nFft);

    final int positiveBins = nFft ~/ 2 + 1;

    // ------------------------------------------------------------
    // Calculate Mel power spectrogram
    // ------------------------------------------------------------

    final List<List<double>> melPower = List.generate(
      nMels,
      (_) => List<double>.filled(frameCount, 0.0),
    );

    for (int frame = 0; frame < frameCount; frame++) {
      final int start = frame * hop;

      for (int i = 0; i < nFft; i++) {
        final int sampleIndex = start + i;

        final double sample = sampleIndex < samples.length
            ? samples[sampleIndex]
            : 0.0;

        window[i] = sample * _hannWindow![i];
      }

      for (int i = 0; i < nFft; i++) {
        real[i] = window[i];
        imag[i] = 0.0;
      }

      _fft(real, imag);

      for (int mel = 0; mel < nMels; mel++) {
        double sum = 0.0;

        final List<double> filter = filterbank[mel];

        for (int k = 0; k < positiveBins; k++) {
          final double weight = filter[k];

          if (weight != 0.0) {
            final double r = real[k];

            final double im = imag[k];

            final double power = (r * r + im * im) / nFft;

            sum += power * weight;
          }
        }

        melPower[mel][frame] = sum;
      }
    }

    // ------------------------------------------------------------
    // Find global maximum
    // ------------------------------------------------------------

    double globalMax = 0.0;

    for (int mel = 0; mel < nMels; mel++) {
      for (int frame = 0; frame < frameCount; frame++) {
        if (melPower[mel][frame] > globalMax) {
          globalMax = melPower[mel][frame];
        }
      }
    }

    if (globalMax <= 0.0) {
      globalMax = 1e-10;
    }

    final double referenceDb = 10.0 * log(globalMax) / ln10;

    final double minimumDb = referenceDb - 80.0;

    // ------------------------------------------------------------
    // Convert to Log-Mel dB
    // ------------------------------------------------------------

    for (int mel = 0; mel < nMels; mel++) {
      for (int frame = 0; frame < frameCount; frame++) {
        double value = melPower[mel][frame];

        if (value < 1e-10) {
          value = 1e-10;
        }

        double db = 10.0 * log(value) / ln10;

        if (db < minimumDb) {
          db = minimumDb;
        }

        result[mel][frame] = db;
      }
    }

    return result;
  }

  // ============================================================
  // NORMALIZATION
  // ============================================================

  void _normalizeInPlace(List<Float32List> matrix) {
    double sum = 0.0;
    int count = 0;

    for (final row in matrix) {
      for (final value in row) {
        sum += value;
        count++;
      }
    }

    if (count == 0) {
      return;
    }

    final double mean = sum / count;

    double variance = 0.0;

    for (final row in matrix) {
      for (final value in row) {
        final double difference = value - mean;

        variance += difference * difference;
      }
    }

    final double std = sqrt(variance / count);

    final double denominator = std + 1e-6;

    for (int rowIndex = 0; rowIndex < matrix.length; rowIndex++) {
      for (
        int columnIndex = 0;
        columnIndex < matrix[rowIndex].length;
        columnIndex++
      ) {
        matrix[rowIndex][columnIndex] =
            ((matrix[rowIndex][columnIndex] - mean) / denominator);
      }
    }
  }

  // ============================================================
  // HANN WINDOW
  // ============================================================

  List<double> _buildHannWindow() {
    final List<double> window = List<double>.filled(fftSize, 0.0);

    for (int i = 0; i < fftSize; i++) {
      window[i] = 0.5 * (1.0 - cos(2.0 * pi * i / fftSize));
    }

    return window;
  }

  // ============================================================
  // MEL FILTERBANK
  // ============================================================

  List<List<double>> _buildMelFilterbank(int numberOfMelFilters) {
    final int numberOfFftBins = fftSize ~/ 2 + 1;

    const double minFrequency = 0.0;

    const double maxFrequency = sampleRate / 2.0;

    final double minMel = _hzToMel(minFrequency);

    final double maxMel = _hzToMel(maxFrequency);

    final List<double> melPoints = List<double>.generate(
      numberOfMelFilters + 2,
      (index) {
        return minMel + (maxMel - minMel) * index / (numberOfMelFilters + 1);
      },
    );

    final List<double> frequencies = melPoints.map(_melToHz).toList();

    final List<int> bins = frequencies.map((frequency) {
      int bin = ((fftSize + 1) * frequency / sampleRate).floor();

      if (bin < 0) {
        bin = 0;
      }

      if (bin >= numberOfFftBins) {
        bin = numberOfFftBins - 1;
      }

      return bin;
    }).toList();

    final List<List<double>> filterbank = List.generate(
      numberOfMelFilters,
      (_) => List<double>.filled(numberOfFftBins, 0.0),
    );

    for (int m = 0; m < numberOfMelFilters; m++) {
      final int left = bins[m];

      final int center = bins[m + 1];

      final int right = bins[m + 2];

      // ----------------------------------------------------------
      // Rising slope
      // ----------------------------------------------------------

      if (center > left) {
        for (int k = left; k < center && k < numberOfFftBins; k++) {
          filterbank[m][k] = (k - left) / (center - left);
        }
      }

      // ----------------------------------------------------------
      // Falling slope
      // ----------------------------------------------------------

      if (right > center) {
        for (int k = center; k < right && k < numberOfFftBins; k++) {
          filterbank[m][k] = (right - k) / (right - center);
        }
      }

      // ----------------------------------------------------------
      // Slaney-style area normalization
      // ----------------------------------------------------------

      final double bandwidth = frequencies[m + 2] - frequencies[m];

      if (bandwidth > 0) {
        final double scale = 2.0 / bandwidth;

        for (int k = 0; k < numberOfFftBins; k++) {
          filterbank[m][k] *= scale;
        }
      }
    }

    return filterbank;
  }

  // ============================================================
  // DCT MATRIX
  // ============================================================

  List<List<double>> _buildDctMatrix(int outputSize, int inputSize) {
    final List<List<double>> matrix = List.generate(
      outputSize,
      (_) => List<double>.filled(inputSize, 0.0),
    );

    final double scale = sqrt(2.0 / inputSize);

    for (int k = 0; k < outputSize; k++) {
      for (int n = 0; n < inputSize; n++) {
        double value = cos(pi / inputSize * (n + 0.5) * k);

        if (k == 0) {
          value *= 1.0 / sqrt(2.0);
        }

        matrix[k][n] = value * scale;
      }
    }

    return matrix;
  }

  // ============================================================
  // FFT
  // ============================================================

  void _fft(Float64List real, Float64List imag) {
    final int n = real.length;

    // ------------------------------------------------------------
    // Bit reversal
    // ------------------------------------------------------------

    int j = 0;

    for (int i = 1; i < n; i++) {
      int bit = n >> 1;

      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }

      j ^= bit;

      if (i < j) {
        final double tempReal = real[i];

        real[i] = real[j];

        real[j] = tempReal;

        final double tempImag = imag[i];

        imag[i] = imag[j];

        imag[j] = tempImag;
      }
    }

    // ------------------------------------------------------------
    // FFT butterfly stages
    // ------------------------------------------------------------

    for (int length = 2; length <= n; length <<= 1) {
      final double angle = -2.0 * pi / length;

      final double wLenReal = cos(angle);

      final double wLenImag = sin(angle);

      for (int i = 0; i < n; i += length) {
        double currentReal = 1.0;

        double currentImag = 0.0;

        final int half = length >> 1;

        for (int k = 0; k < half; k++) {
          final int evenIndex = i + k;

          final int oddIndex = i + k + half;

          final double oddReal =
              real[oddIndex] * currentReal - imag[oddIndex] * currentImag;

          final double oddImag =
              real[oddIndex] * currentImag + imag[oddIndex] * currentReal;

          final double evenReal = real[evenIndex];

          final double evenImag = imag[evenIndex];

          real[evenIndex] = evenReal + oddReal;

          imag[evenIndex] = evenImag + oddImag;

          real[oddIndex] = evenReal - oddReal;

          imag[oddIndex] = evenImag - oddImag;

          final double nextReal =
              currentReal * wLenReal - currentImag * wLenImag;

          currentImag = currentReal * wLenImag + currentImag * wLenReal;

          currentReal = nextReal;
        }
      }
    }
  }

  // ============================================================
  // CENTER PADDING
  // ============================================================

  List<double> _centerPad(List<double> samples) {
    final int padding = fftSize ~/ 2;

    final List<double> result = List<double>.filled(
      samples.length + padding * 2,
      0.0,
    );

    for (int i = 0; i < samples.length; i++) {
      result[i + padding] = samples[i];
    }

    return result;
  }

  // ============================================================
  // RESAMPLING
  // ============================================================

  List<double> _resampleLinear(
    List<double> input,
    int inputRate,
    int outputRate,
  ) {
    if (inputRate == outputRate) {
      return List<double>.from(input);
    }

    if (input.isEmpty) {
      return <double>[];
    }

    final int outputLength = (input.length * outputRate / inputRate).round();

    final List<double> output = List<double>.filled(outputLength, 0.0);

    final double ratio = inputRate / outputRate;

    for (int i = 0; i < outputLength; i++) {
      final double sourcePosition = i * ratio;

      final int index = sourcePosition.floor();

      final double fraction = sourcePosition - index;

      if (index >= input.length - 1) {
        output[i] = input.last;
      } else {
        output[i] =
            input[index] * (1.0 - fraction) + input[index + 1] * fraction;
      }
    }

    return output;
  }

  // ============================================================
  // WAV READER
  // ============================================================

  Future<_WavData> _readWav(String path) async {
    final File file = File(path);

    final Uint8List bytes = await file.readAsBytes();

    if (bytes.length < 44) {
      throw Exception('Invalid WAV file: file is too small.');
    }

    final ByteData data = ByteData.sublistView(bytes);

    final String riff = String.fromCharCodes(bytes.sublist(0, 4));

    final String wave = String.fromCharCodes(bytes.sublist(8, 12));

    if (riff != 'RIFF' || wave != 'WAVE') {
      throw Exception('Invalid WAV file.');
    }

    int offset = 12;

    int? audioFormat;
    int? channels;
    int? sampleRateValue;
    int? bitsPerSample;

    int? dataOffset;
    int? dataSize;

    while (offset + 8 <= bytes.length) {
      final String chunkId = String.fromCharCodes(
        bytes.sublist(offset, offset + 4),
      );

      final int chunkSize = data.getUint32(offset + 4, Endian.little);

      final int chunkDataStart = offset + 8;

      if (chunkId == 'fmt ') {
        if (chunkDataStart + 16 > bytes.length) {
          throw Exception('Invalid WAV fmt chunk.');
        }

        audioFormat = data.getUint16(chunkDataStart, Endian.little);

        channels = data.getUint16(chunkDataStart + 2, Endian.little);

        sampleRateValue = data.getUint32(chunkDataStart + 4, Endian.little);

        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataStart;

        dataSize = min(chunkSize, bytes.length - chunkDataStart);
      }

      offset = chunkDataStart + chunkSize;

      // WAV chunks are word aligned.
      if (offset % 2 != 0) {
        offset++;
      }

      if (dataOffset != null && audioFormat != null) {
        break;
      }
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRateValue == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataSize == null) {
      throw Exception('Could not read WAV format information.');
    }

    if (audioFormat != 1) {
      throw Exception('Unsupported WAV format. Only PCM WAV is supported.');
    }

    if (bitsPerSample != 16) {
      throw Exception(
        'Unsupported WAV bit depth. Only 16-bit PCM is supported.',
      );
    }

    if (channels != 1 && channels != 2) {
      throw Exception('Unsupported number of WAV channels.');
    }

    final int bytesPerSample = bitsPerSample ~/ 8;

    final int totalSamples = dataSize ~/ (bytesPerSample * channels);

    final List<double> samples = List<double>.filled(totalSamples, 0.0);

    int byteIndex = dataOffset;

    for (int i = 0; i < totalSamples; i++) {
      double sample = 0.0;

      for (int channel = 0; channel < channels; channel++) {
        if (byteIndex + 2 > bytes.length) {
          break;
        }

        final int pcm = data.getInt16(byteIndex, Endian.little);

        byteIndex += 2;

        sample += pcm / 32768.0;
      }

      sample /= channels;

      samples[i] = sample;
    }

    return _WavData(samples: samples, sampleRate: sampleRateValue);
  }

  // ============================================================
  // MEL CONVERSION
  // ============================================================

  double _hzToMel(double hz) {
    return 2595.0 * log(1.0 + hz / 700.0) / ln10;
  }

  double _melToHz(double mel) {
    return 700.0 * (pow(10.0, mel / 2595.0) - 1.0);
  }
}

// ================================================================
// WAV DATA HOLDER
// ================================================================

class _WavData {
  final List<double> samples;
  final int sampleRate;

  _WavData({required this.samples, required this.sampleRate});
}
