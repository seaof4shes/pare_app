import 'package:flutter/material.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int selectedFilter = 0;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardColor = Color(0xFFEFF4F3);
  static const Color backgroundColor = Color(0xFFF7F8FA);

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

  Widget _filterButton(String text, int index) {
    final selected = selectedFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedFilter = index),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: selected ? primaryBlue : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> item) {
    final bool safe = item['safe'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              item['category'] == 'Calls' ? Icons.phone : Icons.sms,
              color: primaryBlue,
              size: 22,
            ),
          ),

          const SizedBox(width: 14),

          // Text content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 4),

                // Date
                Text(
                  item['date'],
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),

                const SizedBox(height: 10),

                // Result
                Row(
                  children: [
                    Icon(
                      safe
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color: safe ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      item['result'],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: safe ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Confidence
                Text(
                  "Confidence: ${item['confidence']}",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),

                const SizedBox(height: 2),

                // Action
                Text(
                  "Action: ${item['action']}",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = filteredHistory;

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
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          "No history yet",
                          style: TextStyle(fontSize: 15, color: Colors.black45),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (_, i) => _historyTile(items[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
