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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final SmsDetectionService smsModel = SmsDetectionService();
  final CallDetectionService callDetectionService = CallDetectionService();

  static const EventChannel smsEventChannel = EventChannel(
    'pare_app/sms_receiver',
  );

  StreamSubscription? _smsSubscription;

  // Design tokens
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
  static const String keyCallAutoBlock = 'call_auto_block';
  static const String keyMsgScamAlerts = 'msg_scam_alerts';

  bool _isActivated = false;
  bool _isLoading = true;
  bool _modelReady = false;
  bool _smsListenerStarted = false;
  bool _callListenerStarted = false;

  bool _callDetection = true;
  bool _msgDetection = true;
  bool _callAutoBlock = true;
  bool _msgScamAlerts = true;
  bool _isAnalyzingUpload = false;

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

    // Check for application/model updates after
    // the Home screen has initialized.
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

    // Re-check after returning from Updates.
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

    final callAutoBlock = prefs.getBool(keyCallAutoBlock) ?? true;

    final msgScamAlerts = prefs.getBool(keyMsgScamAlerts) ?? true;

    if (!mounted) return;

    setState(() {
      _username = savedUsername;
      _isActivated = activated;
      _callDetection = callDetection;
      _msgDetection = msgDetection;
      _callAutoBlock = callAutoBlock;
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
          debugPrint("Message Detection is OFF. Skipping SMS detection.");
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
  // CALL DETECTION
  // ============================================================

  Future<void> startCallDetection() async {
    if (!_isActivated || !_callDetection) {
      return;
    }

    if (_callListenerStarted) return;

    try {
      await callDetectionService.start();

      _callListenerStarted = true;

      debugPrint("📞 Call detection is enabled and ready.");
    } catch (e) {
      debugPrint("❌ Call detection error: $e");
    }
  }

  Future<void> _stopCallDetection() async {
    if (!_callListenerStarted) return;

    await callDetectionService.stop();

    _callListenerStarted = false;

    debugPrint("🛑 Call detection stopped from Home");
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Enable permissions in settings"),
            action: SnackBarAction(
              label: "OPEN SETTINGS",
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newState ? "Protection Activated" : "Protection Deactivated",
        ),
        backgroundColor: newState
            ? Colors.green.shade700
            : Colors.grey.shade700,
      ),
    );
  }

  // ============================================================
  // VOICE LIVE TEST
  // ============================================================

  Future<void> _onTestVoiceDetection() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Recording voice for 6 seconds...")),
    );

    final result = await callDetectionService.runVoiceDemoTest();

    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Voice detection failed. Please try again."),
          backgroundColor: Colors.red,
        ),
      );

      return;
    }

    _showVoiceResultDialog(result, source: "Live Recording");
  }

  // ============================================================
  // VOICE FILE UPLOAD
  // ============================================================

  Future<void> _onUploadVoiceFile() async {
    if (_isAnalyzingUpload) return;

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
        return;
      }

      final file = File(selectedFile.path!);

      final fileName = selectedFile.name;

      if (!await file.exists()) {
        debugPrint('❌ Selected file does not exist: ${file.path}');
        return;
      }

      debugPrint('✅ Selected audio file: $fileName');

      debugPrint('📁 Path: ${file.path}');

      debugPrint('📦 Size: ${await file.length()} bytes');

      if (!mounted) return;

      setState(() {
        _isAnalyzingUpload = true;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Analyzing $fileName...")));

      try {
        final result = await callDetectionService.analyzeAudioFile(
          file.path,
          fileName: fileName,
        );

        if (!mounted) return;

        setState(() {
          _isAnalyzingUpload = false;
        });

        debugPrint('🎤 Upload Voice Result: $result');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result?['label']?.toString() ?? 'Voice analysis completed.',
            ),
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('❌ Uploaded voice analysis error: $e');

        debugPrint('$stackTrace');

        if (!mounted) return;

        setState(() {
          _isAnalyzingUpload = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Voice analysis failed: $e")));
      }
    } catch (e, stackTrace) {
      debugPrint('❌ File picker error: $e');

      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isAnalyzingUpload = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Unable to open audio files: $e")));
    }
  }

  // ============================================================
  // VOICE RESULT DIALOG
  // ============================================================

  void _showVoiceResultDialog(Map result, {required String source}) {
    final label = result['label']?.toString() ?? 'Unknown';

    final confidence = result['confidence'] ?? 0.0;

    final action = result['action']?.toString() ?? 'Logged';

    final isSynthetic =
        label.toLowerCase().contains('ai') ||
        label.toLowerCase().contains('synthetic');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              isSynthetic
                  ? Icons.warning_amber_rounded
                  : Icons.verified_rounded,
              color: isSynthetic ? dangerColor : successColor,
            ),
            const SizedBox(width: 8),
            const Text("Voice Analysis"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source,
              style: const TextStyle(fontSize: 12, color: mutedColor),
            ),
            const SizedBox(height: 10),
            _dialogRow("Result", label),
            _dialogRow("Confidence", "$confidence%"),
            _dialogRow("Action", action),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            "$label: ",
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
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

        // ======================================================
        // UPDATE BELL
        // ======================================================
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
                    onPressed: _onTestVoiceDetection,
                    icon: const Icon(Icons.mic, size: 18, color: Colors.white),
                    label: const Text(
                      "Record Live",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
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
                    onPressed: _isAnalyzingUpload ? null : _onUploadVoiceFile,
                    icon: _isAnalyzingUpload
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
                      _isAnalyzingUpload ? "Analyzing..." : "Upload File",
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
            "Upload a call recording or voice memo to check for AI voice cloning.",
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
                Icons.phone_in_talk_outlined,
                _callDetection
                    ? "Detect AI scam audios"
                    : "Audio detection is currently off",
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
                Icons.graphic_eq_rounded,
                "Analyze voices — live or uploaded — for AI cloning",
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
                icon: Icons.phone_in_talk_outlined,
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
              _statusRow(
                icon: Icons.call_end_outlined,
                label: "Audio",
                statusText: _callAutoBlock
                    ? "Assisted blocking on"
                    : "Assisted blocking off",
                isOn: _callAutoBlock,
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
