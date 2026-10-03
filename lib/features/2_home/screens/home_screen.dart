import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pare_app/services/notification_service.dart';
import 'package:pare_app/services/app_update_service.dart';
import 'package:pare_app/core/security/local_crypto_service.dart';

import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/permissions/permission_service.dart';
import 'package:pare_app/core/ml/sms_detection_service.dart';
import 'package:pare_app/core/ml/call_detection_service.dart';

import 'package:pare_app/features/4_settings/screens/updates_screen.dart';
import 'package:pare_app/features/3_history/screens/history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final SmsDetectionService smsModel = SmsDetectionService();

  // Kept for the current working voice implementation.
  // This service currently handles the recording/upload analysis flow.
  final CallDetectionService callDetectionService = CallDetectionService();

  static const EventChannel smsEventChannel = EventChannel(
    'pare_app/sms_receiver',
  );

  StreamSubscription? _smsSubscription;

  // ============================================================
  // DESIGN TOKENS
  // ============================================================

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color successColor = Color(0xFF1C8756);
  static const Color dangerColor = Color(0xFFC0392B);
  static const Color tintBlue = Color.fromRGBO(9, 44, 86, 0.07);

  static const String _prefKey = 'protection_activated';

  static const String keyCallDetection = 'call_detection';
  static const String keyMsgDetection = 'msg_detection';
  static const String keyMsgScamAlerts = 'msg_scam_alerts';

  bool _isActivated = false;
  bool _isLoading = true;
  bool _modelReady = false;
  bool _smsListenerStarted = false;
  bool _callListenerStarted = false;

  bool _callDetection = true;
  bool _msgDetection = true;
  bool _msgScamAlerts = true;

  bool _isRecordingVoice = false;
  bool _isUploadingVoice = false;

  String _username = "Username";

  // ============================================================
  // UPDATE STATE
  // ============================================================

  bool _updateAvailable = false;
  bool _appUpdateAvailable = false;
  bool _smsModelUpdateAvailable = false;
  bool _voiceModelUpdateAvailable = false;

  String _installedAppVersion = '';
  String _latestAppVersion = '';

  int _installedSmsModelVersion = 1;
  int _latestSmsModelVersion = 1;

  int _installedVoiceModelVersion = 4;
  int _latestVoiceModelVersion = 4;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    initializeApp();
  }

  Future<void> refreshHomeSettings() async {
    await _loadState();
  }

  Future<void> initializeApp() async {
    await _loadState();
    await initModel();

    await _checkForUpdates();
  }

  // ============================================================
  // UPDATE CHECK
  // ============================================================

  Future<void> _checkForUpdates() async {
    debugPrint('🔍 Home: Checking for P.A.R.E. updates...');

    try {
      final updateService = AppUpdateService();

      final result = await updateService.checkForUpdates();

      if (result['success'] != true) {
        debugPrint('⚠️ Home update check was unsuccessful.');
        debugPrint('⚠️ Error: ${result['error']}');
        return;
      }

      if (!mounted) return;

      setState(() {
        _updateAvailable = result['anyUpdateAvailable'] == true;

        _appUpdateAvailable = result['appUpdateAvailable'] == true;

        _smsModelUpdateAvailable = result['smsModelUpdateAvailable'] == true;

        _voiceModelUpdateAvailable =
            result['voiceModelUpdateAvailable'] == true;

        _installedAppVersion = result['installedAppVersion']?.toString() ?? '';

        _latestAppVersion = result['latestAppVersion']?.toString() ?? '';

        _installedSmsModelVersion = _toInt(result['installedSmsModelVersion']);

        _latestSmsModelVersion = _toInt(result['latestSmsModelVersion']);

        _installedVoiceModelVersion = _toInt(
          result['installedVoiceModelVersion'],
        );

        _latestVoiceModelVersion = _toInt(result['latestVoiceModelVersion']);
      });

      debugPrint('🔔 Home update available: $_updateAvailable');
      debugPrint('📱 App update: $_appUpdateAvailable');
      debugPrint('📩 SMS model update: $_smsModelUpdateAvailable');
      debugPrint('🎤 Voice model update: $_voiceModelUpdateAvailable');
    } catch (e, stackTrace) {
      debugPrint('❌ Home update check failed: $e');
      debugPrint('$stackTrace');
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _openUpdatesScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UpdatesScreen(
          appUpdateAvailable: _appUpdateAvailable,
          smsModelUpdateAvailable: _smsModelUpdateAvailable,
          voiceModelUpdateAvailable: _voiceModelUpdateAvailable,
          installedAppVersion: _installedAppVersion,
          latestAppVersion: _latestAppVersion,
          installedSmsModelVersion: _installedSmsModelVersion,
          latestSmsModelVersion: _latestSmsModelVersion,
          installedVoiceModelVersion: _installedVoiceModelVersion,
          latestVoiceModelVersion: _latestVoiceModelVersion,
        ),
      ),
    );

    await _checkForUpdates();
  }

  // ============================================================
  // MODEL
  // ============================================================

  Future<void> initModel() async {
    try {
      await smsModel.loadModel();

      if (!mounted) return;

      setState(() {
        _modelReady = true;
      });

      debugPrint("✅ SMS model loaded");
    } catch (e) {
      debugPrint("❌ Model error: $e");
    }
  }

  // ============================================================
  // STATE
  // ============================================================

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    final activated = prefs.getBool(_prefKey) ?? false;

    final savedUsername = prefs.getString('username') ?? "Username";

    final callDetection = prefs.getBool(keyCallDetection) ?? true;

    final msgDetection = prefs.getBool(keyMsgDetection) ?? true;

    final msgScamAlerts = prefs.getBool(keyMsgScamAlerts) ?? true;

    if (!mounted) return;

    setState(() {
      _username = savedUsername;
      _isActivated = activated;
      _callDetection = callDetection;
      _msgDetection = msgDetection;
      _msgScamAlerts = msgScamAlerts;
      _isLoading = false;
    });

    if (!_isActivated) {
      await _stopSmsListener();
      await _stopCallDetection();
      return;
    }

    if (_msgDetection) {
      await startSmsListener();
    } else {
      await _stopSmsListener();
    }

    if (_callDetection) {
      await startCallDetection();
    } else {
      await _stopCallDetection();
    }
  }

  // ============================================================
  // SMS LISTENER
  // ============================================================

  Future<void> startSmsListener() async {
    if (_smsListenerStarted) return;

    final status = await Permission.sms.request();

    if (!status.isGranted) {
      debugPrint("❌ SMS permission denied");
      return;
    }

    _smsListenerStarted = true;

    _smsSubscription = smsEventChannel.receiveBroadcastStream().listen(
      (event) async {
        final data = Map<String, dynamic>.from(event);

        final senderNumber = data['senderNumber']?.toString() ?? 'Unknown';

        final senderName = data['senderName']?.toString() ?? '';

        final smsBody = data['body']?.toString() ?? '';

        final sender = senderName.isNotEmpty ? senderName : senderNumber;

        debugPrint("📩 NATIVE SMS RECEIVED");
        debugPrint("Sender: $sender");
        debugPrint("Body: $smsBody");

        if (smsBody.isEmpty) return;

        final prefs = await SharedPreferences.getInstance();

        final activated = prefs.getBool(_prefKey) ?? false;

        final msgDetection = prefs.getBool(keyMsgDetection) ?? true;

        if (!activated) {
          debugPrint("Protection is OFF. Skipping SMS detection.");
          return;
        }

        if (!msgDetection) {
          debugPrint(
            "Message Detection is OFF. "
            "Skipping SMS detection.",
          );
          return;
        }

        if (!_modelReady) {
          debugPrint("SMS model is not ready yet.");
          return;
        }

        await detectIncomingSms(
          message: smsBody,
          sender: sender,
          senderNumber: senderNumber,
        );
      },
      onError: (error) {
        debugPrint("❌ Native SMS listener error: $error");
      },
    );

    debugPrint("✅ Native SMS listener started");
  }

  Future<void> _stopSmsListener() async {
    if (!_smsListenerStarted) return;

    await _smsSubscription?.cancel();

    _smsSubscription = null;
    _smsListenerStarted = false;

    debugPrint("🛑 SMS listener stopped");
  }

  // ============================================================
  // AUDIO DETECTION
  // ============================================================

  Future<void> startCallDetection() async {
    if (!_isActivated || !_callDetection) {
      return;
    }

    if (_callListenerStarted) return;

    try {
      await callDetectionService.start();

      _callListenerStarted = true;

      debugPrint("🎤 Audio detection is enabled and ready.");
    } catch (e) {
      debugPrint("❌ Audio detection error: $e");
    }
  }

  Future<void> _stopCallDetection() async {
    if (!_callListenerStarted) return;

    await callDetectionService.stop();

    _callListenerStarted = false;

    debugPrint("🛑 Audio detection stopped from Home");
  }

  // ============================================================
  // SMS DETECTION
  // ============================================================

  double _calculateHybridConfidence({
    required double mlScore,
    required int keywordScore,
  }) {
    final keywordConfidence = (keywordScore / 12).clamp(0.0, 1.0);

    double hybridScore = (mlScore * 0.7) + (keywordConfidence * 0.3);

    if (keywordScore >= 8 && hybridScore < 0.75) {
      hybridScore = 0.75 + ((keywordScore - 8) * 0.03);
    }

    if (keywordScore >= 4 && hybridScore < 0.50) {
      hybridScore = 0.50 + ((keywordScore - 4) * 0.03);
    }

    return hybridScore.clamp(0.0, 0.99);
  }

  Future<void> detectIncomingSms({
    required String message,
    required String sender,
    required String senderNumber,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final msgDetection = prefs.getBool(keyMsgDetection) ?? true;

      final msgScamAlerts = prefs.getBool(keyMsgScamAlerts) ?? true;

      if (!msgDetection) {
        debugPrint("Message Detection is OFF. SMS ignored.");
        return;
      }

      final result = await smsModel.predict(message);

      final label = result.label;
      final mlScore = result.scamProbability;

      final keywordScore = result.keywordScore;

      final risk = result.riskLevel;

      final finalConfidence = _calculateHybridConfidence(
        mlScore: mlScore,
        keywordScore: keywordScore,
      );

      final isRisky =
          label.toLowerCase() == 'scam' || label.toLowerCase() == 'suspicious';

      final alertShown = isRisky && msgScamAlerts;

      final historyId = await saveSmsToHistory(
        sender: sender,
        senderNumber: senderNumber,
        message: message,
        label: label,
        score: finalConfidence,
        alertShown: alertShown,
        keywordScore: keywordScore,
        riskLevel: risk,
      );

      if (alertShown) {
        await NotificationService.showScamSmsNotification(
          sender: sender,
          message: message,
          payload: historyId.toString(),
          riskLevel: risk,
        );
      }

      debugPrint("📩 SMS from $sender");

      debugPrint(
        "Result: $label | "
        "Risk: $risk | "
        "ML Score: $mlScore | "
        "Final Confidence: $finalConfidence",
      );

      debugPrint("Keyword Score: ${result.keywordScore}");
    } catch (e) {
      debugPrint("❌ SMS prediction error: $e");
    }
  }

  Future<int> saveSmsToHistory({
    required String sender,
    required String senderNumber,
    required String message,
    required String label,
    required double score,
    required bool alertShown,
    required int keywordScore,
    required String riskLevel,
  }) async {
    final isScam = label.toLowerCase() == 'scam';

    final isSuspicious = label.toLowerCase() == 'suspicious';

    final isRisky = isScam || isSuspicious;

    final prefs = await SharedPreferences.getInstance();

    final currentPhone = prefs.getString('phone') ?? '';

    final id = await DatabaseHelper.instance.insertHistory({
      'userPhone': currentPhone,
      'name': sender,
      'senderNumber': senderNumber,
      'type': 'SMS Message',
      'message': await LocalCryptoService.instance.encryptText(message),
      'result': isRisky ? 'Scam / Suspicious' : 'Safe / Legit',
      'confidence': score,
      'action': isRisky
          ? (alertShown ? 'Alert Shown' : 'Logged Only')
          : 'Allowed',
      'category': 'Messages',
      'safe': isRisky ? 0 : 1,
      'keywordScore': keywordScore,
      'riskLevel': riskLevel,
      'dateTime': DateTime.now().toIso8601String(),
    });

    debugPrint("✅ Saved SMS to SQLite history with ID: $id");

    return id;
  }

  // ============================================================
  // VOICE / AUDIO HISTORY
  // ============================================================

  Future<int> saveVoiceToHistory({
    required Map result,
    required String source,
    String? fileName,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final currentPhone = prefs.getString('phone') ?? '';

    final label = result['label']?.toString() ?? 'Unknown';

    var confidence =
        double.tryParse(result['confidence']?.toString() ?? '') ?? 0.0;

    // Voice history stores confidence as 0-100.
    if (confidence <= 1.0) {
      confidence *= 100;
    }

    confidence = confidence.clamp(0.0, 100.0).toDouble();

    final lower = label.toLowerCase();

    final isHuman = lower.contains('human');

    final isSynthetic =
        lower.contains('ai') ||
        lower.contains('deepfake') ||
        lower.contains('synthetic');

    final isSuspicious =
        lower.contains('suspicious') || lower.contains('possible');

    final riskLevel = isSynthetic
        ? 'HIGH'
        : isSuspicious
        ? 'MEDIUM'
        : isHuman
        ? 'LOW'
        : 'MEDIUM';

    final safe = isHuman && !isSynthetic && !isSuspicious;

    // Current audio behavior:
    // Human Voice -> Allowed
    // Suspicious / Possible AI -> Alert Shown
    // AI / Deepfake -> Alert Shown
    final action = safe ? 'Allowed' : 'Alert Shown';

    final id = await DatabaseHelper.instance.insertHistory({
      'userPhone': currentPhone,
      'name': fileName ?? 'Recorded Sample',
      'senderNumber': source == 'Recorded Sample'
          ? 'Microphone Sample'
          : 'Uploaded File',
      'type': 'Audio',
      'message': await LocalCryptoService.instance.encryptText(
        'Voice analysis result: $label',
      ),
      'result': label,
      'confidence': confidence,
      'action': action,
      'category': 'Audio',
      'safe': safe ? 1 : 0,
      'keywordScore': 0,
      'riskLevel': riskLevel,
      'dateTime': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Saved voice analysis to SQLite history with ID: $id');

    return id;
  }

  // ============================================================
  // P.A.R.E. POPUP HELPERS
  // ============================================================

  Dialog _pareDialogShell({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.fromLTRB(20, 28, 20, 16),
  }) {
    return Dialog(
      backgroundColor: surfaceColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  Widget _dialogPrimaryButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _dialogTextButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _alertIconBadge(IconData icon, Color color, {bool solid = false}) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: solid
          ? Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: Colors.white),
            )
          : Icon(icon, size: 30, color: color),
    );
  }

  Widget _statusPill(String text, bool isOn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isOn
            ? successColor.withValues(alpha: 0.10)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isOn ? successColor : mutedColor,
        ),
      ),
    );
  }

  Widget _alertRows(List<_AlertRow> rows) {
    final hasBadges = rows.any((row) => row.badge != null);

    if (hasBadges) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      rows[i].icon,
                      size: 18,
                      color: rows[i].badgeOn ? accentBlue : mutedColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: const TextStyle(fontSize: 14, color: inkColor),
                      ),
                    ),
                    if (rows[i].badge != null)
                      _statusPill(rows[i].badge!, rows[i].badgeOn),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            children: [
              _iconBadge(rows[i].icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rows[i].label,
                  style: const TextStyle(fontSize: 14, color: inkColor),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ============================================================
  // P.A.R.E. ALERT POPUP
  // ============================================================

  Future<void> _showPAREAlert({
    required String title,
    required String message,
    IconData icon = Icons.info_outline,
    Color iconColor = primaryBlue,
    String buttonText = "OK",
    VoidCallback? onButtonPressed,
    String? secondaryButtonText,
    bool solidIcon = false,
    List<_AlertRow> rows = const [],
  }) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return _pareDialogShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _alertIconBadge(icon, iconColor, solid: solidIcon),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: inkColor,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: mutedColor,
                  height: 1.5,
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 18),
                _alertRows(rows),
              ],
              const SizedBox(height: 20),
              _dialogPrimaryButton(buttonText, () {
                Navigator.pop(dialogContext);
                onButtonPressed?.call();
              }),
              if (secondaryButtonText != null) ...[
                const SizedBox(height: 2),
                _dialogTextButton(
                  secondaryButtonText,
                  () => Navigator.pop(dialogContext),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // VOICE RESULT DIALOG
  // ============================================================

  void _showVoiceResultDialog(
    Map result, {
    required String source,
    int? historyId,
  }) {
    final label = result['label']?.toString() ?? 'Unknown';

    var confidence =
        double.tryParse(result['confidence']?.toString() ?? '') ?? 0.0;

    // Accept either 0-100 or 0-1.
    if (confidence <= 1.0) {
      confidence *= 100;
    }

    confidence = confidence.clamp(0.0, 100.0).toDouble();

    final lower = label.toLowerCase();

    final isSynthetic =
        lower.contains('ai') ||
        lower.contains('deepfake') ||
        lower.contains('synthetic');

    final isUnknown =
        lower.contains('suspicious') ||
        lower.contains('possible') ||
        lower == 'unknown';

    // ==========================================================
    // AUDIO ACTION
    //
    // Human Voice
    //     -> Allowed
    //
    // Suspicious / Possible AI
    //     -> Alert Shown
    //
    // AI / Deepfake
    //     -> Alert Shown
    //
    // This intentionally does NOT use result['action']
    // because the older voice service may still return
    // "Blocked" for AI/deepfake results.
    // ==========================================================

    final action = isSynthetic || isUnknown ? 'Alert Shown' : 'Allowed';

    final Color tone = isSynthetic
        ? dangerColor
        : isUnknown
        ? primaryBlue
        : successColor;

    final IconData toneIcon = isSynthetic
        ? Icons.warning_amber_rounded
        : isUnknown
        ? Icons.help_outline_rounded
        : Icons.check_circle_outline_rounded;

    final String verdict = isSynthetic
        ? 'Likely AI-generated voice'
        : isUnknown
        ? 'Possible AI-generated voice'
        : 'Likely a human voice';

    final String advice = isSynthetic
        ? "Be careful with this audio. "
              "Do not share codes, passwords, "
              "or send money based only on "
              "this voice."
        : isUnknown
        ? "P.A.R.E. could not make a clear "
              "determination. Try a longer "
              "or clearer audio sample."
        : "No strong signs of AI-generated "
              "voice were detected. Still "
              "verify unexpected requests "
              "independently.";

    final IconData sourceIcon = source.toLowerCase().contains('record')
        ? Icons.mic_none_rounded
        : Icons.upload_file_outlined;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _pareDialogShell(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SOURCE CHIP + CLOSE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sourceIcon, size: 14, color: mutedColor),
                        const SizedBox(width: 6),
                        Text(
                          source,
                          style: const TextStyle(
                            fontSize: 12,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(dialogContext),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: mutedColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // VERDICT
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(toneIcon, size: 26, color: tone),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Result',
                          style: TextStyle(fontSize: 12, color: mutedColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          verdict,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: inkColor,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // CONFIDENCE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Confidence',
                    style: TextStyle(fontSize: 13, color: mutedColor),
                  ),
                  Text(
                    '${confidence.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: confidence / 100,
                  minHeight: 8,
                  backgroundColor: borderColor,
                  valueColor: AlwaysStoppedAnimation<Color>(tone),
                ),
              ),

              const SizedBox(height: 14),

              // ACTION
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Action',
                    style: TextStyle(fontSize: 13, color: mutedColor),
                  ),
                  Flexible(
                    child: Text(
                      action,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: action == 'Allowed' ? successColor : dangerColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ADVICE
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: accentBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        advice,
                        style: const TextStyle(
                          fontSize: 13,
                          color: inkColor,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // HISTORY BUTTON
              if (historyId != null)
                _dialogPrimaryButton('View Detection History', () {
                  Navigator.pop(dialogContext);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(openHistoryId: historyId),
                    ),
                  );
                }),

              if (historyId != null) const SizedBox(height: 4),

              // GOT IT
              _dialogTextButton('Got it', () => Navigator.pop(dialogContext)),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // PROTECTION ACTIVATION
  // ============================================================

  Future<void> _onActivate() async {
    final prefs = await SharedPreferences.getInstance();

    final newState = !_isActivated;

    if (newState) {
      final granted = await PermissionService()
          .requestAllProtectionPermissions();

      await NotificationService.init();

      if (!granted) {
        if (!mounted) return;

        await _showPAREAlert(
          title: "Allow access to turn on protection",
          message:
              "P.A.R.E. needs the required "
              "permissions to activate its "
              "protection features. You can "
              "enable them in your device settings.",
          icon: Icons.lock_open_rounded,
          iconColor: primaryBlue,
          buttonText: "Open settings",
          secondaryButtonText: "Not now",
          onButtonPressed: () {
            openAppSettings();
          },
          rows: const [
            _AlertRow(icon: Icons.sms_outlined, label: "Read incoming SMS"),
            _AlertRow(
              icon: Icons.mic_none_rounded,
              label: "Use the microphone",
            ),
            _AlertRow(
              icon: Icons.notifications_none_rounded,
              label: "Send you alerts",
            ),
          ],
        );

        return;
      }

      await prefs.setBool(_prefKey, true);

      await _loadState();
    } else {
      await prefs.setBool(_prefKey, false);

      await _stopSmsListener();
      await _stopCallDetection();

      if (!mounted) return;

      setState(() {
        _isActivated = false;
      });
    }

    if (!mounted) return;

    await _showPAREAlert(
      title: newState ? "Protection is on" : "Protection is off",
      message: newState
          ? "P.A.R.E. is now watching in "
                "the background. You'll get an "
                "alert if something looks like "
                "a scam."
          : "Automatic detection has stopped. "
                "You can turn protection back on "
                "anytime from Home.",
      icon: newState ? Icons.verified_user_rounded : Icons.shield_outlined,
      iconColor: newState ? successColor : mutedColor,
      solidIcon: newState,
      buttonText: "Done",
      rows: newState
          ? [
              _AlertRow(
                icon: Icons.graphic_eq_rounded,
                label: "Audio detection",
                badge: _callDetection ? "On" : "Off",
                badgeOn: _callDetection,
              ),
              _AlertRow(
                icon: Icons.chat_bubble_outline,
                label: "Message detection",
                badge: _msgDetection ? "On" : "Off",
                badgeOn: _msgDetection,
              ),
            ]
          : const [],
    );
  }

  // ============================================================
  // VOICE / AUDIO RECORDING
  // ============================================================

  Future<void> _onTestVoiceDetection() async {
    if (_isRecordingVoice || _isUploadingVoice) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isRecordingVoice = true;
    });

    try {
      final result = await callDetectionService.runVoiceDemoTest();

      if (!mounted) return;

      setState(() {
        _isRecordingVoice = false;
      });

      if (result == null) {
        await _showPAREAlert(
          title: "Voice Detection Failed",
          message:
              "P.A.R.E. was unable to analyze "
              "the recorded sample. Please try again.",
          icon: Icons.error_outline,
          iconColor: dangerColor,
        );

        return;
      }

      final historyId = await saveVoiceToHistory(
        result: result,
        source: 'Recorded Sample',
      );

      if (!mounted) return;

      _showVoiceResultDialog(
        result,
        source: "Recorded Sample",
        historyId: historyId,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Voice recording analysis error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isRecordingVoice = false;
      });

      await _showPAREAlert(
        title: "Voice Analysis Failed",
        message:
            "P.A.R.E. was unable to analyze "
            "the recorded sample. Please try again.",
        icon: Icons.error_outline,
        iconColor: dangerColor,
      );
    }
  }

  // ============================================================
  // VOICE / AUDIO FILE UPLOAD
  // ============================================================

  Future<void> _onUploadVoiceFile() async {
    if (_isRecordingVoice || _isUploadingVoice) {
      return;
    }

    try {
      debugPrint('📁 Opening audio file picker...');

      final picked = await FilePicker.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (picked == null || picked.files.isEmpty) {
        debugPrint('📁 No audio file selected.');
        return;
      }

      final selectedFile = picked.files.single;

      if (selectedFile.path == null) {
        debugPrint('❌ Selected file has no accessible path.');

        if (!mounted) return;

        await _showPAREAlert(
          title: "File Unavailable",
          message:
              "The selected audio file could "
              "not be accessed. Please choose "
              "another file.",
          icon: Icons.audio_file_outlined,
          iconColor: dangerColor,
        );

        return;
      }

      final file = File(selectedFile.path!);

      final fileName = selectedFile.name;

      if (!await file.exists()) {
        debugPrint(
          '❌ Selected file does not exist: '
          '${file.path}',
        );

        if (!mounted) return;

        await _showPAREAlert(
          title: "File Not Found",
          message:
              "The selected audio file could "
              "not be found. Please choose "
              "another file.",
          icon: Icons.folder_off_outlined,
          iconColor: dangerColor,
        );

        return;
      }

      debugPrint('✅ Selected audio file: $fileName');
      debugPrint('📁 Path: ${file.path}');
      debugPrint('📦 Size: ${await file.length()} bytes');

      if (!mounted) return;

      setState(() {
        _isUploadingVoice = true;
      });

      try {
        final result = await callDetectionService.analyzeAudioFile(
          file.path,
          fileName: fileName,
        );

        if (!mounted) return;

        setState(() {
          _isUploadingVoice = false;
        });

        debugPrint('🎤 Upload Voice Result: $result');

        if (result == null) {
          await _showPAREAlert(
            title: "Analysis Unavailable",
            message:
                "P.A.R.E. could not determine "
                "a result for the uploaded audio.",
            icon: Icons.help_outline,
            iconColor: primaryBlue,
          );

          return;
        }

        final historyId = await saveVoiceToHistory(
          result: result,
          source: 'Uploaded Audio',
          fileName: fileName,
        );

        if (!mounted) return;

        _showVoiceResultDialog(
          result,
          source: "Uploaded Audio",
          historyId: historyId,
        );
      } catch (e, stackTrace) {
        debugPrint('❌ Uploaded voice analysis error: $e');
        debugPrint('$stackTrace');

        if (!mounted) return;

        setState(() {
          _isUploadingVoice = false;
        });

        await _showPAREAlert(
          title: "Voice Analysis Failed",
          message:
              "P.A.R.E. was unable to analyze "
              "the selected audio file. Please "
              "try another file or try again.",
          icon: Icons.error_outline,
          iconColor: dangerColor,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ File picker error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      await _showPAREAlert(
        title: "Unable to Open Audio",
        message:
            "P.A.R.E. could not open the audio "
            "file picker. Please try again.",
        icon: Icons.folder_off_outlined,
        iconColor: dangerColor,
      );
    }
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _header() {
    final initial = _username.isNotEmpty ? _username[0].toUpperCase() : "U";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: primaryBlue,
                shape: BoxShape.circle,
              ),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "P.A.R.E",
                  style: TextStyle(
                    color: primaryBlue,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  "Protecting All Random Exchange",
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),

        // UPDATE BELL
        Row(
          children: [
            GestureDetector(
              onTap: _openUpdatesScreen,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _updateAvailable ? tintBlue : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        color: _updateAvailable ? primaryBlue : mutedColor,
                        size: 25,
                      ),
                    ),
                    if (_updateAvailable)
                      Positioned(
                        right: 0,
                        top: -2,
                        child: Container(
                          width: 17,
                          height: 17,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: dangerColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            "!",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 40,
              height: 40,
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // UI HELPERS
  // ============================================================

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _cardHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: inkColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: mutedColor)),
      ],
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: borderColor);

  Widget _iconBadge(IconData icon, {Color? tint}) {
    final color = tint ?? primaryBlue;

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: color),
    );
  }

  Widget _bulletRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _iconBadge(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: inkColor,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusRow({
    required IconData icon,
    required String label,
    required String statusText,
    required bool isOn,
  }) {
    return Row(
      children: [
        _iconBadge(icon, tint: isOn ? accentBlue : mutedColor),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: inkColor,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isOn
                ? successColor.withValues(alpha: 0.10)
                : Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isOn ? successColor : mutedColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _greeting(String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Hello, $_username",
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: inkColor,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: mutedColor,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // VOICE CARD
  // ============================================================

  Widget _voiceCheckCard() {
    final isBusy = _isRecordingVoice || _isUploadingVoice;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(
            "Voice Authenticity Check",
            "Find out if a voice is human or AI-generated",
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isBusy ? null : _onTestVoiceDetection,
                    icon: _isRecordingVoice
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.mic, size: 18, color: Colors.white),
                    label: Text(
                      _isRecordingVoice ? "Analyzing..." : "Record Sample",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      disabledBackgroundColor: primaryBlue.withValues(
                        alpha: 0.55,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : _onUploadVoiceFile,
                    icon: _isUploadingVoice
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryBlue,
                            ),
                          )
                        : const Icon(
                            Icons.upload_file_outlined,
                            size: 18,
                            color: primaryBlue,
                          ),
                    label: Text(
                      _isUploadingVoice ? "Analyzing..." : "Upload File",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: primaryBlue,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: primaryBlue, width: 1.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          const Text(
            "Record a sample or upload an audio file to check for AI-generated voice.",
            style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.3),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INACTIVE VIEW
  // ============================================================

  Widget _inactiveView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _greeting("Stay protected from scams."),

        const SizedBox(height: 20),

        _card(
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 1),
                decoration: const BoxDecoration(
                  color: successColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "System status",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: mutedColor,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Ready for activation",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: accentBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton(
            onPressed: _onActivate,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              "Activate Protection",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "P.A.R.E will automatically:",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: inkColor,
                ),
              ),

              const SizedBox(height: 16),

              _bulletRow(
                Icons.graphic_eq_rounded,
                _callDetection
                    ? "Analyze audio for possible AI-generated voices"
                    : "Audio analysis is currently off",
              ),

              const SizedBox(height: 12),

              _bulletRow(
                Icons.sms_outlined,
                _msgDetection
                    ? "Detect scam SMS messages"
                    : "Message detection is currently off",
              ),

              const SizedBox(height: 12),

              _bulletRow(
                Icons.notifications_active_outlined,
                _msgScamAlerts
                    ? "Alert you instantly"
                    : "Scam message alerts are currently off",
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: tintBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "You can change these options anytime in Settings.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // ACTIVE VIEW
  // ============================================================

  Widget _activeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _greeting("Your protection is running in the background."),

        const SizedBox(height: 18),

        _card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBadge(Icons.check_rounded, tint: successColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Protection status",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: mutedColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Protection is active",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: inkColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _msgDetection || _callDetection
                          ? "Enabled features are running automatically."
                          : "Protection is active, but all detection options are turned off.",
                      style: const TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardHeader("Detection", "Controls what P.A.R.E checks"),

              const SizedBox(height: 16),

              _statusRow(
                icon: Icons.graphic_eq_rounded,
                label: "Audio",
                statusText: _callDetection ? "On" : "Off",
                isOn: _callDetection,
              ),

              const SizedBox(height: 12),

              _divider(),

              const SizedBox(height: 12),

              _statusRow(
                icon: Icons.chat_bubble_outline,
                label: "Messages",
                statusText: _msgDetection ? "On" : "Off",
                isOn: _msgDetection,
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cardHeader(
                "Response Actions",
                "Controls what P.A.R.E does after detection",
              ),

              const SizedBox(height: 16),

              // Audio currently alerts rather than blocks.
              _statusRow(
                icon: Icons.notifications_active_outlined,
                label: "Audio",
                statusText: "Alerts on",
                isOn: true,
              ),

              const SizedBox(height: 12),

              _divider(),

              const SizedBox(height: 12),

              _statusRow(
                icon: Icons.sms_failed_outlined,
                label: "Messages",
                statusText: _msgScamAlerts
                    ? "Scam alerts on"
                    : "Scam alerts off",
                isOn: _msgScamAlerts,
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        _voiceCheckCard(),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _onActivate,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: dangerColor, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              "Deactivate Protection",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: dangerColor,
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _smsSubscription?.cancel();

    smsModel.close();

    callDetectionService.stop();
    callDetectionService.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryBlue))
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),

                    const SizedBox(height: 18),

                    Expanded(
                      child: SingleChildScrollView(
                        child: _isActivated ? _activeView() : _inactiveView(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================
// ALERT ROW MODEL
// ============================================================

class _AlertRow {
  final IconData icon;
  final String label;

  final String? badge;

  final bool badgeOn;

  const _AlertRow({
    required this.icon,
    required this.label,
    this.badge,
    this.badgeOn = true,
  });
}
