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
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardColor = Color(0xFFEFF4F3);
  static const Color backgroundColor = Color(0xFFF7F8FA);

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
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
    await prefs.remove('phone');
    await prefs.remove('username');
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

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
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

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: primaryBlue,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
          ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: primaryBlue, size: 22),
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
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
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
            inactiveTrackColor: Colors.grey.shade300,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _permissionRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: primaryBlue, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: primaryBlue,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
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
        icon: const Icon(Icons.settings, color: primaryBlue),
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
      height: 55,
      child: ElevatedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout, color: Colors.white),
        label: const Text(
          "Logout",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red.shade500,
          elevation: 3,
          shadowColor: Colors.red.withValues(alpha: 0.3),
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
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),

              const SizedBox(height: 16),

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
                                title: "Auto Block Calls",
                                subtitle:
                                    "Automatically block detected scam calls",
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
                              ),
                            ]),
                            _section("Privacy & Permissions", [
                              const Text(
                                "Allow this app to:",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
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
                              const SizedBox(height: 8),
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
