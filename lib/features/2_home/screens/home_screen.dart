import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/services/notification_service.dart';

import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/permissions/permission_service.dart';
import 'package:pare_app/core/ml/sms_detection_service.dart';
import 'package:pare_app/core/ml/call_detection_service.dart';

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

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardColor = Color(0xFFEFF4F3);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF7F8FA);

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

  String _username = "Username";

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
  }

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

        final sender = data['sender']?.toString() ?? 'Unknown';
        final smsBody = data['body']?.toString() ?? '';

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

        await detectIncomingSms(message: smsBody, sender: sender);
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

  Future<void> startCallDetection() async {
    if (!_isActivated || !_callDetection) return;
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
        message: message,
        label: label,
        score: finalConfidence,
        alertShown: alertShown,
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
        "Result: $label | Risk: $risk | ML Score: $mlScore | Final Confidence: $finalConfidence",
      );
      debugPrint("Keyword Score: ${result.keywordScore}");
    } catch (e) {
      debugPrint("❌ SMS prediction error: $e");
    }
  }

  Future<int> saveSmsToHistory({
    required String sender,
    required String message,
    required String label,
    required double score,
    required bool alertShown,
  }) async {
    final isScam = label.toLowerCase() == 'scam';
    final isSuspicious = label.toLowerCase() == 'suspicious';
    final isRisky = isScam || isSuspicious;

    final id = await DatabaseHelper.instance.insertHistory({
      'name': sender,
      'type': 'SMS Message',
      'message': message,
      'result': isRisky ? 'Scam / Suspicious' : 'Safe / Legit',
      'confidence': score,
      'action': isRisky
          ? (alertShown ? 'Alert Shown' : 'Logged Only')
          : 'Allowed',
      'category': 'Messages',
      'safe': isRisky ? 0 : 1,
      'dateTime': DateTime.now().toIso8601String(),
    });

    debugPrint("✅ Saved SMS to SQLite history with ID: $id");
    return id;
  }

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

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "P.A.R.E",
              style: TextStyle(
                color: primaryBlue,
                fontSize: 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              "Phishing & Response Engine",
              style: TextStyle(
                color: Colors.black45,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color.fromRGBO(9, 44, 86, 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.security, color: primaryBlue, size: 26),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
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
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
    );
  }

  Widget _divider() => Divider(
    height: 1,
    thickness: 1,
    color: Colors.black.withValues(alpha: 0.07),
  );

  Widget _bulletRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: primaryBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
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
        Icon(icon, color: primaryBlue, size: 21),
        const SizedBox(width: 10),
        Text(
          "$label:",
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const Spacer(),
        Text(
          statusText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isOn ? accentBlue : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _greeting(String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Hello,",
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w900,
            color: Colors.black,
            height: 1.1,
          ),
        ),
        Text(
          "$_username!",
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: primaryBlue,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _inactiveView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _greeting("Stay protected from scams."),
        const SizedBox(height: 22),
        _card(
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "System Status",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Ready for Activation",
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
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 66,
          child: ElevatedButton(
            onPressed: _onActivate,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              elevation: 3,
              shadowColor: const Color.fromRGBO(9, 44, 86, 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              "ACTIVATE PROTECTION",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "P.A.R.E will automatically:",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 14),
              _bulletRow(
                Icons.phone_in_talk_outlined,
                _callDetection
                    ? "Detect AI scam calls"
                    : "Call detection is currently OFF",
              ),
              const SizedBox(height: 10),
              _bulletRow(
                Icons.sms_outlined,
                _msgDetection
                    ? "Detect scam SMS messages"
                    : "Message detection is currently OFF",
              ),
              const SizedBox(height: 10),
              _bulletRow(
                Icons.notifications_active_outlined,
                _msgScamAlerts
                    ? "Alert you instantly"
                    : "Scam message alerts are currently OFF",
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(9, 44, 86, 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "You can change these options anytime in Settings.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
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

  Widget _activeView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _greeting("Your protection is running in the background."),
        const SizedBox(height: 20),
        _card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.check_circle, color: Colors.green, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Protection Status",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black45,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Protection is Active",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _msgDetection || _callDetection
                          ? "Enabled features are running automatically."
                          : "Protection is active, but all detection options are turned off.",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
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
              const SizedBox(height: 14),
              _statusRow(
                icon: Icons.phone_in_talk_outlined,
                label: "Calls",
                statusText: _callDetection ? "Detection ON" : "Detection OFF",
                isOn: _callDetection,
              ),
              const SizedBox(height: 10),
              _divider(),
              const SizedBox(height: 10),
              _statusRow(
                icon: Icons.chat_bubble_outline,
                label: "Messages",
                statusText: _msgDetection ? "Detection ON" : "Detection OFF",
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
                "Auto Protection",
                "Controls what P.A.R.E does after detection",
              ),
              const SizedBox(height: 14),
              _statusRow(
                icon: Icons.call_end_outlined,
                label: "Calls",
                statusText: _callAutoBlock ? "Auto Block ON" : "Auto Block OFF",
                isOn: _callAutoBlock,
              ),
              const SizedBox(height: 10),
              _divider(),
              const SizedBox(height: 10),
              _statusRow(
                icon: Icons.sms_failed_outlined,
                label: "Messages",
                statusText: _msgScamAlerts
                    ? "Scam Alerts ON"
                    : "Scam Alerts OFF",
                isOn: _msgScamAlerts,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _onActivate,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.shade700, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              "DEACTIVATE PROTECTION",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.red.shade700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _smsSubscription?.cancel();
    smsModel.close();
    callDetectionService.stop();
    callDetectionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryBlue))
            : Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    const SizedBox(height: 16),
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
