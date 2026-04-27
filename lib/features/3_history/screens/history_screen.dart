import 'package:flutter/material.dart';
import '../../2_home/screens/home_screen.dart';
import '../../4_settings/screens/settings_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int selectedFilter = 0;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color grayBlue = Color(0xFF5B7088);
  static const Color cardColor = Color(0xFFEFF4F3);

  final List<Map<String, dynamic>> history = [
    {
      'name': '+63 123 456 7890',
      'type': 'Voice Call',
      'date': 'March 24, 2026 - 10:15 AM',
      'result': 'AI / Suspicious',
      'confidence': '98% Suspicious',
      'action': 'Call Blocked',
      'category': 'Calls',
      'safe': false,
    },
    {
      'name': 'Killian',
      'type': 'Voice Call',
      'date': 'March 24, 2026 - 8:45 AM',
      'result': 'Safe / Legit',
      'confidence': '98% Safe',
      'action': 'Allowed',
      'category': 'Calls',
      'safe': true,
    },
    {
      'name': 'School Office',
      'type': 'SMS Message',
      'date': 'March 21, 2026 - 7:45 PM',
      'result': 'Safe / Legit',
      'confidence': '94% Safe',
      'action': 'Allowed',
      'category': 'Messages',
      'safe': true,
    },
  ];

  List<Map<String, dynamic>> get filteredHistory {
    if (selectedFilter == 1) {
      return history.where((item) => item['category'] == 'Calls').toList();
    }
    if (selectedFilter == 2) {
      return history.where((item) => item['category'] == 'Messages').toList();
    }
    return history;
  }

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

  Widget _filterButton(String text, int index) {
    final bool selected = selectedFilter == index;

    return GestureDetector(
      onTap: () => setState(() => selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? primaryBlue : grayBlue,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> item) {
    final bool safe = item['safe'] as bool;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.person, size: 34, color: Colors.black),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    color: primaryBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _infoLine("Type:", item['type']),
                _infoLine("Date and Time:", item['date']),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      "Result: ",
                      style: TextStyle(
                        color: primaryBlue,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        item['result'],
                        style: const TextStyle(
                          color: Color(0xFF496985),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      safe ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: safe ? Colors.green : Colors.red,
                      size: 16,
                    ),
                  ],
                ),
                _infoLine("Confidence:", item['confidence']),
                _infoLine("Action:", item['action']),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: "$label ",
              style: const TextStyle(
                color: primaryBlue,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Color(0xFF496985),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _goToSettings() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = filteredHistory;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 16),
              Row(
                children: [
                  _filterButton("All", 0),
                  const SizedBox(width: 8),
                  _filterButton("Calls", 1),
                  const SizedBox(width: 8),
                  _filterButton("Messages", 2),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return _historyCard(items[index]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: primaryBlue,
        unselectedItemColor: Colors.black,
        onTap: (index) {
          if (index == 0) {
            _goToHome();
          } else if (index == 2) {
            _goToSettings();
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
