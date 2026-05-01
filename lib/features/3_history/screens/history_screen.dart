import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final smsHistory = prefs.getStringList('sms_history') ?? [];

    final loadedHistory = smsHistory.map((item) {
      final data = jsonDecode(item) as Map<String, dynamic>;
      final label = data['label']?.toString() ?? 'legit';
      final score = (data['score'] as num?)?.toDouble() ?? 0.0;

      return {
        'name': data['sender'] ?? 'Unknown',
        'type': 'SMS Message',
        'message': data['message'] ?? '',
        'date': _formatDate(data['dateTime']),
        'result': label == 'scam' ? 'Scam / Suspicious' : 'Safe / Legit',
        'confidence': '${(score * 100).toStringAsFixed(1)}%',
        'action': label == 'scam' ? 'Alert Shown' : 'Allowed',
        'category': 'Messages',
        'safe': label != 'scam',
      };
    }).toList();

    if (!mounted) return;

    setState(() {
      history = loadedHistory.reversed.toList();
    });
  }

  String _formatDate(dynamic rawDate) {
    if (rawDate == null) return 'Unknown date';

    final date = DateTime.tryParse(rawDate.toString());
    if (date == null) return 'Unknown date';

    final hour = date.hour > 12
        ? date.hour - 12
        : date.hour == 0
        ? 12
        : date.hour;

    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '${date.month}/${date.day}/${date.year} - $hour:$minute $period';
  }

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
    final String message = item['message'] ?? '';

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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              item['category'] == 'Calls' ? Icons.phone : Icons.sms,
              color: primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item['date'],
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 10),
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
                Text(
                  "Confidence: ${item['confidence']}",
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 2),
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
                child: RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 250),
                            Center(
                              child: Text(
                                "No history yet",
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.black45,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _historyTile(items[i]),
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
