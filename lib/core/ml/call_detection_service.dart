import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:phone_state/phone_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/core/ml/call_analysis_service.dart';

class CallDetectionService {
  static final CallDetectionService _instance =
      CallDetectionService._internal();

  factory CallDetectionService() => _instance;

  CallDetectionService._internal();

  final CallAnalysisService _callAnalysisService = CallAnalysisService();

  StreamSubscription<PhoneState>? _phoneSub;

  bool _isDetecting = false;
  bool _hasAnalyzedCurrentCall = false;

  // Track last seen status to deduplicate repeated identical events
  PhoneStateStatus? _lastStatus;
  String? _lastNumber;

  Future<void> start() async {
    await _phoneSub?.cancel();

    _phoneSub = PhoneState.stream.listen((PhoneState event) async {
      final status = event.status;
      final number = (event.number != null && event.number!.isNotEmpty)
          ? event.number
          : _lastNumber;

      // ── Deduplicate: ignore repeated identical status events ──
      if (status == _lastStatus) return;
      _lastStatus = status;

      if (number != null) _lastNumber = number;

      debugPrint("📞 Phone state: $status, number: $number");

      if (status == PhoneStateStatus.CALL_STARTED &&
          !_hasAnalyzedCurrentCall &&
          !_isDetecting) {
        _hasAnalyzedCurrentCall = true;
        await _handleIncomingCall(_lastNumber);
      }

      if (status == PhoneStateStatus.CALL_ENDED) {
        debugPrint("📞 Call ended. Ready for next call.");
        _hasAnalyzedCurrentCall = false;
        _isDetecting = false;
        _lastNumber = null;
        _lastStatus = null; // reset so next CALL_STARTED is fresh
      }
    });

    debugPrint('✅ Call listener started');
  }

  Future<void> stop() async {
    await _phoneSub?.cancel();
    _phoneSub = null;

    _isDetecting = false;
    _hasAnalyzedCurrentCall = false;
    _lastNumber = null;
    _lastStatus = null;

    debugPrint('🛑 Call listener stopped');
  }

  Future<void> _handleIncomingCall(String? phoneNumber) async {
    if (_isDetecting) return;

    final prefs = await SharedPreferences.getInstance();
    final isActivated = prefs.getBool('protection_activated') ?? false;
    final callDetectionEnabled = prefs.getBool('call_detection') ?? true;

    if (!isActivated || !callDetectionEnabled) return;

    _isDetecting = true;

    try {
      debugPrint(
        '📞 Incoming call detected: ${phoneNumber ?? "Unknown Number"}',
      );
      debugPrint('🔍 Starting automatic call detection...');

      // Wait for the call to be answered and audio routing to stabilise.
      // 5 s is the minimum reliable delay on most Android devices before
      // the microphone input reflects actual call audio rather than silence.
      await Future.delayed(const Duration(seconds: 5));

      // Bail out if the call already ended while we were waiting
      if (!_hasAnalyzedCurrentCall) {
        debugPrint('📞 Call ended before analysis could start. Skipping.');
        return;
      }

      final result = await _callAnalysisService.analyzeCall(
        callerName: 'Incoming Caller',
        callerNumber: phoneNumber ?? 'Unknown Number',
      );

      if (result == null) {
        debugPrint('❌ Call detection cancelled or permission denied');
        return;
      }

      debugPrint('📞 Call Detection Result: ${result['label']}');
      debugPrint('Confidence: ${result['confidence']}');
    } catch (e) {
      debugPrint('❌ Call detection error: $e');
    } finally {
      _isDetecting = false;
    }
  }

  void dispose() {
    _callAnalysisService.dispose();
  }
}
