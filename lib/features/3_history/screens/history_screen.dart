import 'package:flutter/material.dart';
import 'package:pare_app/core/database/database_helper.dart';

class HistoryScreen extends StatefulWidget {
  final int? openHistoryId;

  const HistoryScreen({super.key, this.openHistoryId});

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
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.openHistoryId != oldWidget.openHistoryId &&
        widget.openHistoryId != null) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    final loadedHistory = await DatabaseHelper.instance.getHistory();
    if (!mounted) return;

    setState(() {
      history = loadedHistory.map((data) {
        final confidenceValue =
            ((data['confidence'] as num?)?.toDouble() ?? 0.0);
        final confidencePercent = confidenceValue * 100;

        final storedAction = (data['action'] as String? ?? '').trim();
        String action;
        if (storedAction.isNotEmpty) {
          action = storedAction;
        } else if (confidencePercent >= 75) {
          action = 'Blocked';
        } else if (confidencePercent >= 40) {
          action = 'Alert Shown';
        } else {
          action = 'Allowed';
        }

        // Derive riskLevel label for display
        final storedRisk = (data['riskLevel'] as String? ?? '').trim();
        String riskLevel;
        if (storedRisk.isNotEmpty) {
          riskLevel = storedRisk;
        } else if (confidencePercent >= 75) {
          riskLevel = 'HIGH';
        } else if (confidencePercent >= 40) {
          riskLevel = 'MEDIUM';
        } else {
          riskLevel = 'LOW';
        }

        final keywordScore = data['keywordScore'] as int? ?? 0;

        return {
          'id': data['id'],
          'name': _formatSender(data['name']),
          'type': data['type'] ?? 'SMS Message',
          'message': data['message'] ?? '',
          'date': _formatDate(data['dateTime']),
          'result': data['result'] ?? 'Unknown',
          'confidenceRaw': confidencePercent,
          'confidence': '${confidencePercent.toStringAsFixed(1)}%',
          'riskLevel': riskLevel,
          'keywordScore': keywordScore,
          'action': action,
          'category': data['category'] ?? 'Messages',
          'safe': data['safe'] == 1,
        };
      }).toList();
    });

    if (widget.openHistoryId != null) {
      final matchedItem = history.firstWhere(
        (item) => item['id'] == widget.openHistoryId,
        orElse: () => {},
      );

      if (matchedItem.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showMessageBottomSheet(context, matchedItem);
          }
        });
      }
    }
  }

  String _formatSender(dynamic raw) {
    if (raw == null) return '+63 000 000 0000';
    final s = raw.toString().trim();
    if (s.isEmpty) return '+63 000 000 0000';
    if (s.contains(RegExp(r'[a-zA-Z]'))) return s;

    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && digits.startsWith('9')) {
      return '+63 ${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
    } else if (digits.length == 11 && digits.startsWith('09')) {
      return '+63 ${digits.substring(1, 4)} ${digits.substring(4, 7)} ${digits.substring(7)}';
    } else if (digits.length == 12 && digits.startsWith('63')) {
      return '+63 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
    }
    return s;
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

  Color _confidenceColor(double percent, bool safe) {
    if (safe) return const Color(0xFF388E3C);
    if (percent >= 75) return const Color(0xFFD32F2F);
    if (percent >= 40) return const Color(0xFFF57C00);
    return const Color(0xFF388E3C);
  }

  // ─── Action badge ─────────────────────────────────────────────────────────────

  Widget _actionBadge(String action) {
    Color bg;
    Color fg;
    IconData icon;

    switch (action) {
      case 'Blocked':
      case 'Call Blocked':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFD32F2F);
        icon = Icons.block_rounded;
        break;
      case 'Alert Shown':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFF57C00);
        icon = Icons.warning_amber_rounded;
        break;
      default:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF388E3C);
        icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            action,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Risk level badge (shown only in bottom sheet) ────────────────────────────

  Widget _riskBadge(String riskLevel) {
    Color bg;
    Color fg;
    String label;

    switch (riskLevel) {
      case 'HIGH':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFD32F2F);
        label = 'High Risk';
        break;
      case 'MEDIUM':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFF57C00);
        label = 'Medium Risk';
        break;
      default:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF388E3C);
        label = 'Low Risk';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  // ─── Detail row for bottom sheet ──────────────────────────────────────────────

  Widget _detailRow(String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black45,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  // ─── Bottom sheet ─────────────────────────────────────────────────────────────

  void _showMessageBottomSheet(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final double confidenceRaw = item['confidenceRaw'] as double;
    final bool safe = item['safe'];
    final int keywordScore = item['keywordScore'] as int? ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Sender row
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primaryBlue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      item['category'] == 'Calls'
                          ? Icons.phone_rounded
                          : Icons.sms_rounded,
                      color: primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['name'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          item['date'],
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

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message body
                      const Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black45,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (item['message'] as String).isNotEmpty
                              ? item['message']
                              : '(No message content)',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.6,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Detection details section
                      const Text(
                        'Detection Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black45,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _detailRow(
                        'Result',
                        Row(
                          children: [
                            Icon(
                              safe
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_rounded,
                              size: 14,
                              color: safe
                                  ? const Color(0xFF388E3C)
                                  : const Color(0xFFD32F2F),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              item['result'],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: safe
                                    ? const Color(0xFF388E3C)
                                    : const Color(0xFFD32F2F),
                              ),
                            ),
                          ],
                        ),
                      ),

                      _detailRow('Risk Level', _riskBadge(item['riskLevel'])),

                      _detailRow('Action Taken', _actionBadge(item['action'])),

                      _detailRow(
                        'Confidence',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: confidenceRaw / 100,
                                minHeight: 7,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _confidenceColor(confidenceRaw, safe),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['confidence'],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _confidenceColor(confidenceRaw, safe),
                              ),
                            ),
                          ],
                        ),
                      ),

                      _detailRow(
                        'Keyword Score',
                        Text(
                          '$keywordScore ${keywordScore == 1 ? 'point' : 'points'}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),

                      _detailRow(
                        'Type',
                        Text(
                          item['type'],
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),
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

  // ─── Confirm clear ────────────────────────────────────────────────────────────

  Future<void> _confirmClearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear History?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'This will permanently delete all scam detection records. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Color(0xFFD32F2F)),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.clearHistory();
      await _loadHistory();
    }
  }

  // ─── Filtered list ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get filteredHistory {
    if (selectedFilter == 1) {
      return history.where((item) => item['category'] == 'Calls').toList();
    }
    if (selectedFilter == 2) {
      return history.where((item) => item['category'] == 'Messages').toList();
    }
    return history;
  }

  // ─── Header ───────────────────────────────────────────────────────────────────

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

  // ─── Filter buttons ───────────────────────────────────────────────────────────

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

  // ─── Record count + clear button ─────────────────────────────────────────────

  Widget _recordCountRow(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$count ${count == 1 ? 'record' : 'records'}',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (count > 0)
          GestureDetector(
            onTap: _confirmClearHistory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: primaryBlue, width: 1.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 13,
                    color: primaryBlue,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ─── History tile (clean — no extra detail here) ──────────────────────────────

  Widget _historyTile(Map<String, dynamic> item) {
    final bool safe = item['safe'];
    final String message = item['message'] ?? '';
    final double confidenceRaw = item['confidenceRaw'] as double;
    final bool isLong = message.length > 80;

    return GestureDetector(
      onTap: () => _showMessageBottomSheet(context, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item['category'] == 'Calls' ? Icons.phone : Icons.sms,
                  color: primaryBlue,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + result
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Icon(
                        safe
                            ? Icons.check_circle_outline
                            : Icons.warning_amber_rounded,
                        size: 14,
                        color: safe
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFD32F2F),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item['result'],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: safe
                              ? const Color(0xFF388E3C)
                              : const Color(0xFFD32F2F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Date
                  Text(
                    item['date'],
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                  // Message preview
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                              height: 1.4,
                            ),
                          ),
                        ),
                        if (isLong) ...[
                          const SizedBox(width: 4),
                          const Text(
                            'more',
                            style: TextStyle(
                              fontSize: 11,
                              color: primaryBlue,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Confidence bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: confidenceRaw / 100,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _confidenceColor(confidenceRaw, safe),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item['confidence'],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _confidenceColor(confidenceRaw, safe),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  // Action badge
                  _actionBadge(item['action']),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

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
              const SizedBox(height: 14),
              _recordCountRow(items.length),
              const SizedBox(height: 10),
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
