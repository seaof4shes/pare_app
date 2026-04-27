import 'package:flutter/material.dart';
import '../../2_home/screens/home_screen.dart';
import '../../3_history/screens/history_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardColor = Color(0xFFEFF4F3);

  bool protectCalls = true;
  bool protectSMS = true;
  bool blockCalls = true;
  bool blockSMS = true;

  bool notifPopup = true;
  bool notifSound = true;
  bool notifVibrate = true;

  Widget _header() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "P.A.R.E",
          style: TextStyle(
            color: primaryBlue,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        Icon(Icons.shield, color: primaryBlue, size: 34),
      ],
    );
  }

  Widget _switchTile(String title, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: primaryBlue,
            activeTrackColor: primaryBlue.withValues(alpha: 0.4),
            onChanged: onChanged,
          ),
        ],
      ),
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
            fontSize: 26,
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
          child: Column(children: children),
        ),
      ],
    );
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _goToHistory() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _section("Protection", [
                        _switchTile(
                          "Protect me from scam calls",
                          protectCalls,
                          (v) => setState(() => protectCalls = v),
                        ),
                        _switchTile(
                          "Protect me from scam messages",
                          protectSMS,
                          (v) => setState(() => protectSMS = v),
                        ),
                        _switchTile(
                          "Automatically block scam calls",
                          blockCalls,
                          (v) => setState(() => blockCalls = v),
                        ),
                        _switchTile(
                          "Automatically block scam messages",
                          blockSMS,
                          (v) => setState(() => blockSMS = v),
                        ),
                      ]),
                      _section("Notifications", [
                        _switchTile(
                          "Show a pop-up warning when a scam is detected",
                          notifPopup,
                          (v) => setState(() => notifPopup = v),
                        ),
                        _switchTile(
                          "Play a sound when a scam is detected",
                          notifSound,
                          (v) => setState(() => notifSound = v),
                        ),
                        _switchTile(
                          "Make my phone vibrate when a scam is detected",
                          notifVibrate,
                          (v) => setState(() => notifVibrate = v),
                        ),
                      ]),
                      _section("Privacy & Permissions", [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Manage permissions in your phone settings.",
                            style: TextStyle(fontSize: 15),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        selectedItemColor: primaryBlue,
        unselectedItemColor: Colors.black,
        onTap: (index) {
          if (index == 0) {
            _goToHome();
          } else if (index == 1) {
            _goToHistory();
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: "Home",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "History"),
          BottomNavigationBarItem(
            icon: Icon(Icons.manage_accounts_outlined),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}
