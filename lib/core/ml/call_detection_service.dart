import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
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

  PhoneStateStatus? _lastStatus;
  String? _lastNumber;

  Future<void> start() async {
    await _phoneSub?.cancel();

    _phoneSub = PhoneState.stream.listen((PhoneState event) async {
      final status = event.status;
      final number = (event.number != null && event.number!.isNotEmpty)
          ? event.number
          : _lastNumber;

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
        _lastStatus = null;
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

  Future<String> _getCallerName(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      return 'Unknown Caller';
    }

    try {
      final hasPermission = await FlutterContacts.requestPermission(
        readonly: true,
      );

      if (!hasPermission) {
        debugPrint('❌ Contacts permission denied');
        return phoneNumber;
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);

      final incomingDigits = _normalizeNumber(phoneNumber);

      for (final contact in contacts) {
        for (final phone in contact.phones) {
          final contactDigits = _normalizeNumber(phone.number);

          if (contactDigits.isEmpty) continue;

          if (incomingDigits.endsWith(contactDigits) ||
              contactDigits.endsWith(incomingDigits)) {
            final name = contact.displayName.trim();

            if (name.isNotEmpty) {
              return name;
            }
          }
        }
      }

      return phoneNumber;
    } catch (e) {
      debugPrint('❌ Contact lookup error: $e');
      return phoneNumber;
    }
  }

  String _normalizeNumber(String number) {
    var digits = number.replaceAll(RegExp(r'\D'), '');

    if (digits.startsWith('63') && digits.length >= 12) {
      digits = '0${digits.substring(2)}';
    }

    return digits;
  }

  Future<void> _handleIncomingCall(String? phoneNumber) async {
    if (_isDetecting) return;

    final prefs = await SharedPreferences.getInstance();
    final isActivated = prefs.getBool('protection_activated') ?? false;
    final callDetectionEnabled = prefs.getBool('call_detection') ?? true;

    if (!isActivated || !callDetectionEnabled) return;

    _isDetecting = true;

    try {
      final callerNumber = phoneNumber ?? 'Unknown Number';
      final callerName = await _getCallerName(phoneNumber);

      debugPrint('📞 Incoming call detected: $callerName ($callerNumber)');
      debugPrint('🔍 Starting automatic call detection...');

      await Future.delayed(const Duration(seconds: 5));

      if (!_hasAnalyzedCurrentCall) {
        debugPrint('📞 Call ended before analysis could start. Skipping.');
        return;
      }

      final result = await _callAnalysisService.analyzeCall(
        callerName: callerName,
        callerNumber: callerNumber,
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

  Future<Map<String, dynamic>?> runVoiceDemoTest() async {
    if (_isDetecting) return null;

    _isDetecting = true;

    try {
      debugPrint('🎤 Starting manual voice detection demo...');

      final result = await _callAnalysisService.analyzeCall(
        callerName: 'Voice Demo Test',
        callerNumber: 'Microphone Demo',
      );

      if (result == null) {
        debugPrint('❌ Voice demo cancelled or permission denied');
        return null;
      }

      debugPrint('🎤 Voice Demo Result: ${result['label']}');
      debugPrint('Confidence: ${result['confidence']}');

      return result;
    } catch (e) {
      debugPrint('❌ Voice demo error: $e');
      return null;
    } finally {
      _isDetecting = false;
    }
  }

  /// NEW: analyze a WAV file the user picked from storage (instead of
  /// recording live audio) for human vs AI-generated voice.
  Future<Map<String, dynamic>?> analyzeAudioFile(
    String filePath, {
    String? fileName,
  }) async {
    if (_isDetecting) return null;

    _isDetecting = true;

    try {
      final resolvedName = fileName ?? filePath.split('/').last;

      debugPrint('📁 Starting uploaded audio analysis: $resolvedName');

      final result = await _callAnalysisService.analyzeUploadedFile(
        filePath,
        fileName: resolvedName,
      );

      if (result == null) {
        debugPrint('❌ Uploaded audio analysis returned no result');
        return null;
      }

      debugPrint('📁 Upload Analysis Result: ${result['label']}');
      debugPrint('Confidence: ${result['confidence']}');

      return result;
    } catch (e) {
      debugPrint('❌ Uploaded audio analysis error: $e');
      return null;
    } finally {
      _isDetecting = false;
    }
  }

  void dispose() {
    _callAnalysisService.dispose();
  }
}