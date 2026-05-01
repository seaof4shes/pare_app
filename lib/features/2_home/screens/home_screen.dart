import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/services/notification_service.dart';

import 'package:pare_app/core/permissions/permission_service.dart';
import 'package:pare_app/services/sms_model_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SmsModelService smsModel = SmsModelService();

  static const EventChannel smsEventChannel = EventChannel(
    'pare_app/sms_receiver',
  );

  StreamSubscription? _smsSubscription;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardColor = Color(0xFFEFF4F3);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF7F8FA);

  bool _isActivated = false;
  bool _isLoading = true;
  bool _modelReady = false;
  bool _smsListenerStarted = false;

  bool _callDetection = true;
  bool _msgDetection = true;
  bool _callAutoBlock = true;
  bool _msgScamAlerts = true;

  String _username = "Username";

  static const String _prefKey = 'protection_activated';

  @override
  void initState() {
    super.initState();
    initializeApp();
  }

  Future<void> initializeApp() async {
    await _loadState();
    await initModel();

    if (_isActivated) {
      await startSmsListener();
    }
  }

  Future<void> initModel() async {
    try {
      await smsModel.loadModel();
      _modelReady = true;
      debugPrint("✅ SMS model loaded");
    } catch (e) {
      debugPrint("❌ Model error: $e");
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
        if (!_isActivated || !_msgDetection) return;
        if (!_modelReady) return;

        await detectIncomingSms(message: smsBody, sender: sender);
      },
      onError: (error) {
        debugPrint("❌ Native SMS listener error: $error");
      },
    );

    debugPrint("✅ Native SMS listener started");
  }

  Future<void> detectIncomingSms({
    required String message,
    required String sender,
  }) async {
    try {
      final result = await smsModel.predictSms(message);

      final label = result['label'] as String;
      final score = result['score'] as double;

      await saveSmsToHistory(
        sender: sender,
        message: message,
        label: label,
        score: score,
      );

      if (!mounted) return;

      if (label == 'scam' && _msgScamAlerts) {
        await NotificationService.showScamSmsNotification(
          sender: sender,
          message: message,
        );
      }

      debugPrint("📩 SMS from $sender");
      debugPrint("Result: $label | Score: $score");
    } catch (e) {
      debugPrint("❌ SMS prediction error: $e");
    }
  }

  Future<void> saveSmsToHistory({
    required String sender,
    required String message,
    required String label,
    required double score,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('sms_history') ?? [];

    final record = {
      'type': 'SMS',
      'sender': sender,
      'message': message,
      'label': label,
      'score': score,
      'dateTime': DateTime.now().toIso8601String(),
    };

    history.add(jsonEncode(record));

    await prefs.setStringList('sms_history', history);

    debugPrint("✅ Saved to SMS history");
  }

  void refreshHomeSettings() {
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    final activated = prefs.getBool(_prefKey) ?? false;
    final savedUsername = prefs.getString('username') ?? "Username";
    final callDetection = prefs.getBool('call_detection') ?? true;
    final msgDetection = prefs.getBool('msg_detection') ?? true;
    final callAutoBlock = prefs.getBool('call_auto_block') ?? true;
    final msgScamAlerts = prefs.getBool('msg_scam_alerts') ?? true;

    if (mounted) {
      setState(() {
        _username = savedUsername;
        _isActivated = activated;
        _callDetection = callDetection;
        _msgDetection = msgDetection;
        _callAutoBlock = callAutoBlock;
        _msgScamAlerts = msgScamAlerts;
        _isLoading = false;
      });
    }
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

      await startSmsListener();
    }

    await prefs.setBool(_prefKey, newState);

    if (!mounted) return;

    setState(() => _isActivated = newState);

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
        const Text(
          "P.A.R.E",
          style: TextStyle(
            color: primaryBlue,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
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
        Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87)),
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
            fontWeight: FontWeight.w600,
            color: isOn ? accentBlue : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _inactiveView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1.15,
            ),
            children: [
              const TextSpan(text: "Hello,\n"),
              TextSpan(
                text: "$_username!",
                style: const TextStyle(color: primaryBlue),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          "Stay protected from scams.",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
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
              _bulletRow(Icons.phone_in_talk_outlined, "Detect AI scam calls"),
              const SizedBox(height: 10),
              _bulletRow(Icons.sms_outlined, "Detect scam SMS messages"),
              const SizedBox(height: 10),
              _bulletRow(
                Icons.notifications_active_outlined,
                "Alert you instantly",
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
                  "No need to press anything again once activated.",
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
        RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1.15,
            ),
            children: [
              const TextSpan(text: "Hello,\n"),
              TextSpan(
                text: "$_username!",
                style: const TextStyle(color: primaryBlue),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          "Your protection is running in the background.",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 20),
        _card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.check_circle, color: Colors.green, size: 18),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Protection Status",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black45,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Protection is Active",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Calls and messages are being monitored automatically.",
                      style: TextStyle(fontSize: 12, color: Colors.black45),
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
              _cardHeader("Detection", "Detects suspicious activity"),
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
                "Automatic blocking and scam alerts",
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
        Center(
          child: TextButton(
            onPressed: _onActivate,
            child: Text(
              "Deactivate Protection",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade400,
                decoration: TextDecoration.underline,
                decorationColor: Colors.red.shade400,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    smsModel.close();
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
