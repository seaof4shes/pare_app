import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/features/1_auth/screens/login_screen.dart';
import 'package:app_settings/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ---------------------------------------------------------------------
  // Design tokens — mirrored from HomeScreen / HistoryScreen so all three
  // screens read as one cohesive design system.
  // ---------------------------------------------------------------------
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color dangerColor = Color(0xFFC0392B);

  static const String keyCallDetection = 'call_detection';
  static const String keyMsgDetection = 'msg_detection';
  static const String keyCallAutoBlock = 'call_auto_block';
  static const String keyMsgScamAlerts = 'msg_scam_alerts';
  static const String keyNotifSound = 'notif_sound';
  static const String keyNotifVibrate = 'notif_vibrate';

  bool protectCalls = true;
  bool protectSMS = true;
  bool blockCalls = true;
  bool blockSMS = true;

  bool notifSound = true;
  bool notifVibrate = true;

  bool _isLoading = true;

  String _username = "Username";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _username = prefs.getString('username') ?? "Username";

      protectCalls = prefs.getBool(keyCallDetection) ?? true;
      protectSMS = prefs.getBool(keyMsgDetection) ?? true;
      blockCalls = prefs.getBool(keyCallAutoBlock) ?? true;
      blockSMS = prefs.getBool(keyMsgScamAlerts) ?? true;

      notifSound = prefs.getBool(keyNotifSound) ?? true;
      notifVibrate = prefs.getBool(keyNotifVibrate) ?? true;

      _isLoading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();

    // Clear the active session
    await prefs.remove('phone');
    await prefs.remove('username');

    // Require OTP on the next login
    await prefs.setBool('requireOtp', true);
    await prefs.setBool('isLoggedIn', false);

    // Turn off active protection
    await prefs.setBool('protection_activated', false);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openAppSettings() async {
    await AppSettings.openAppSettings();
  }

  // ─── Shared UI pieces (mirrored from HomeScreen / HistoryScreen) ──────────────

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
        SizedBox(
          width: 40,
          height: 40,
          child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.contain),
        ),
      ],
    );
  }

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

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: inkColor,
          ),
        ),
        const SizedBox(height: 10),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _iconBadge(icon, tint: value ? accentBlue : mutedColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
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
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: primaryBlue,
            activeTrackColor: primaryBlue.withValues(alpha: 0.35),
            inactiveThumbColor: Colors.grey.shade500,
            inactiveTrackColor: borderColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _permissionRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _iconBadge(icon, tint: accentBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: primaryBlue,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _managePermissionsButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: _openAppSettings,
        icon: const Icon(Icons.settings, color: primaryBlue, size: 18),
        label: const Text(
          "Manage Permissions",
          style: TextStyle(fontWeight: FontWeight.w800, color: primaryBlue),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: primaryBlue, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout, color: dangerColor, size: 18),
        label: const Text(
          "Logout",
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: dangerColor,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: dangerColor, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),

              const SizedBox(height: 18),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: primaryBlue),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _section("Protection", [
                              _switchTile(
                                icon: Icons.phone_in_talk_outlined,
                                title: "Call Detection",
                                subtitle:
                                    "Detect suspicious or AI-generated calls",
                                value: protectCalls,
                                onChanged: (v) {
                                  setState(() => protectCalls = v);
                                  _saveBool(keyCallDetection, v);
                                },
                              ),
                              _switchTile(
                                icon: Icons.sms_outlined,
                                title: "Message Detection",
                                subtitle: "Detect suspicious scam messages",
                                value: protectSMS,
                                onChanged: (v) {
                                  setState(() => protectSMS = v);
                                  _saveBool(keyMsgDetection, v);
                                },
                              ),
                              _switchTile(
                                icon: Icons.call_end_outlined,
                                title: "Assisted Call Blocking",
                                subtitle:
                                    "Prompt you to block a caller once a scam "
                                    "call is detected",
                                value: blockCalls,
                                onChanged: (v) {
                                  setState(() => blockCalls = v);
                                  _saveBool(keyCallAutoBlock, v);
                                },
                              ),
                              _switchTile(
                                icon: Icons.warning_amber_rounded,
                                title: "Scam Message Alerts",
                                subtitle:
                                    "Show alerts when scam messages are detected",
                                value: blockSMS,
                                onChanged: (v) {
                                  setState(() => blockSMS = v);
                                  _saveBool(keyMsgScamAlerts, v);
                                },
                                isLast: true,
                              ),
                            ]),
                            _section("Notifications", [
                              _switchTile(
                                icon: Icons.volume_up_outlined,
                                title: "Sound Alerts",
                                subtitle:
                                    "Play a sound when a scam is detected",
                                value: notifSound,
                                onChanged: (v) {
                                  setState(() => notifSound = v);
                                  _saveBool(keyNotifSound, v);
                                },
                              ),
                              _switchTile(
                                icon: Icons.vibration_outlined,
                                title: "Vibration Alerts",
                                subtitle:
                                    "Vibrate the phone during scam warnings",
                                value: notifVibrate,
                                onChanged: (v) {
                                  setState(() => notifVibrate = v);
                                  _saveBool(keyNotifVibrate, v);
                                },
                                isLast: true,
                              ),
                            ]),
                            _section("Privacy & Permissions", [
                              const Text(
                                "Allow this app to:",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: inkColor,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _permissionRow(
                                icon: Icons.call,
                                text: "Access incoming calls",
                              ),
                              _permissionRow(
                                icon: Icons.sms,
                                text: "Access incoming messages",
                              ),
                              _permissionRow(
                                icon: Icons.mic,
                                text: "Capture short voice samples",
                              ),
                              _permissionRow(
                                icon: Icons.upload_file_outlined,
                                text: "Access files for voice upload",
                              ),
                              const SizedBox(height: 4),
                              _managePermissionsButton(),
                            ]),
                            _section("About", [
                              _aboutRow("App Name", "P.A.R.E"),
                              _aboutRow("Version", "1.0"),
                              _aboutRow("Developed for", "Capstone Project"),
                            ]),
                            const SizedBox(height: 24),
                            _logoutButton(),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
