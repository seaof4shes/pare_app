import '../widgets/history_detail_sheet.dart';
import '../widgets/history_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pare_app/core/security/private_preferences.dart';

import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/features/widgets/pare_shell.dart';

class HistoryScreen extends StatefulWidget {
  final int? openHistoryId;

  const HistoryScreen({super.key, this.openHistoryId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  int selectedFilter = 0;

  // ---------------------------------------------------------------------
  // Design tokens — shared with the other screens.
  // ---------------------------------------------------------------------
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color segmentColor = Color(0xFFE9EEF5);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color successColor = Color(0xFF1C8756);
  static const Color warningColor = Color(0xFFB9770E);
  static const Color dangerColor = Color(0xFFC0392B);

  static const MethodChannel _blockChannel = MethodChannel(
    'pare_app/block_sender',
  );

  List<Map<String, dynamic>> history = [];
  String _username = "Username";

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadUsername();
    _loadHistory();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadHistory();
  }

  @override
  void didUpdateWidget(covariant HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.openHistoryId != oldWidget.openHistoryId &&
        widget.openHistoryId != null) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await PrivatePreferences.getInstance();
    final savedUsername = prefs.getString('username') ?? "Username";

    if (!mounted) return;

    setState(() {
      _username = savedUsername;
    });
  }

  bool _historyLoading = true;
  String? _historyError;
  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() {
        _historyLoading = true;
        _historyError = null;
      });
    }
    try {
      await _loadHistoryRecords();
    } catch (_) {
      if (mounted) {
        setState(() {
          history = [];
          _historyError =
              'Protected history could not be opened. Sign in again or retry. Your stored records have not been deleted.';
        });
      }
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _loadHistoryRecords() async {
    final prefs = await PrivatePreferences.getInstance();
    final currentPhone = prefs.getString('phone') ?? '';

    final loadedHistory = await DatabaseHelper.instance.getHistory(
      userPhone: currentPhone,
    );

    if (!mounted) return;

    final convertedHistory = loadedHistory.map((data) {
      final confidenceValue = ((data['confidence'] as num?)?.toDouble() ?? 0.0);

      final isAudio = (data['category'] ?? '') == 'Audio';

      final confidencePercent = isAudio
          ? confidenceValue
          : confidenceValue * 100;

      final action = historyActionLabel(data['action'] as String?);
      final riskLevel = historyRiskLabel(data['riskLevel'] as String?);

      final keywordScore = data['keywordScore'] as int? ?? 0;

      return {
        'id': data['id'],
        'name': _formatSender(data['name']),
        'senderNumber': data['senderNumber']?.toString() ?? '',
        'type': data['type'] ?? 'SMS Message',
        'message': data['message'] ?? '',
        'date': _formatDate(data['dateTime']),
        'result': data['result'] ?? 'Unknown',
        'confidenceRaw': confidencePercent,
        'confidence': '${confidencePercent.toStringAsFixed(2)}%',
        'riskLevel': riskLevel,
        'keywordScore': keywordScore,
        'detectionExplanation': data['detectionExplanation'],
        'modelScore': data['modelScore'],
        'modelVersion': data['modelVersion'],
        'action': action,
        'category': data['category'] ?? 'Messages',
        'safe': data['safe'] == 1,
      };
    }).toList();

    if (!mounted) return;

    setState(() {
      history = convertedHistory;
    });

    // If this HistoryScreen was opened from a notification,
    // automatically open that specific history record.
    if (widget.openHistoryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openHistoryRecord(widget.openHistoryId!);
      });
    }
  }

  void _openHistoryRecord(int historyId) {
    final index = history.indexWhere((item) => item['id'] == historyId);

    if (index == -1) {
      debugPrint("⚠️ History record with ID $historyId was not found.");
      return;
    }

    final item = history[index];

    debugPrint("📖 Opening history record ID: $historyId");

    // Automatically switch to Messages filter
    // when the notification came from an SMS.
    if (item['category'] == 'Messages') {
      setState(() {
        selectedFilter = 2;
      });
    }

    // Wait for the HistoryScreen to finish building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _showMessageBottomSheet(context, item);
    });
  }

  Future<void> _openBlockReportSpamFlow(Map<String, dynamic> item) async {
    final senderNumber = (item['senderNumber'] ?? '').toString().trim();

    if (senderNumber.isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The sender number is unavailable for this record.'),
        ),
      );

      return;
    }

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.block_rounded, color: dangerColor),
            SizedBox(width: 8),
            Text(
              'Block Sender?',
              style: TextStyle(fontWeight: FontWeight.w800, color: inkColor),
            ),
          ],
        ),
        content: Text(
          'PARE will open your messaging app '
          'to this sender.\n\n'
          'Sender: ${_formatSender(senderNumber)}\n\n'
          'Select "Block" or "Block & report spam" '
          'in your messaging app to block this sender.',
          style: const TextStyle(color: mutedColor, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text(
              'CANCEL',
              style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'OPEN MESSAGES',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    if (shouldContinue != true) {
      return;
    }

    final historyId = item['id'] as int;

    try {
      // Record completion only after Android successfully opens Messages.
      await _blockChannel.invokeMethod('openSmsConversation', {
        'sender': senderNumber,
      });
      await DatabaseHelper.instance.updateHistoryAction(
        historyId: historyId,
        action: 'Messages opened',
        userPhone: await _getCurrentPhone(),
      );
      await _loadHistory();
    } catch (e) {
      debugPrint('❌ Unexpected block flow error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the messaging application.'),
        ),
      );
    }
  }

  Future<String> _getCurrentPhone() async {
    final prefs = await PrivatePreferences.getInstance();
    return prefs.getString('phone') ?? '';
  }

  String _formatSender(dynamic raw) {
    if (raw == null) return '+63 000 000 0000';

    final s = raw.toString().trim();

    if (s.isEmpty) return '+63 000 000 0000';

    if (s.contains(RegExp(r'[a-zA-Z]'))) return s;

    final digits = s.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 10 && digits.startsWith('9')) {
      return '+63 ${digits.substring(0, 3)} '
          '${digits.substring(3, 6)} '
          '${digits.substring(6)}';
    } else if (digits.length == 11 && digits.startsWith('09')) {
      return '+63 ${digits.substring(1, 4)} '
          '${digits.substring(4, 7)} '
          '${digits.substring(7)}';
    } else if (digits.length == 12 && digits.startsWith('63')) {
      return '+63 ${digits.substring(2, 5)} '
          '${digits.substring(5, 8)} '
          '${digits.substring(8)}';
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

    return '${date.month}/${date.day}/${date.year} - '
        '$hour:$minute $period';
  }

  Color _confidenceColor(double percent, bool safe) {
    if (safe) return successColor;
    if (percent >= 75) return dangerColor;
    if (percent >= 40) return warningColor;
    return successColor;
  }

  // ─── Shared UI pieces ────────────────────────────────────────────────────────

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _iconBadge(IconData icon, {Color? tint}) {
    final color = tint ?? primaryBlue;

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  // ─── Action badge ─────────────────────────────────────────────────────────────

  Widget _actionBadge(String action) {
    Color fg;
    IconData icon;

    switch (action) {
      case 'Blocked':
      case 'Call Blocked':
      case 'High-Risk Alert Shown':
      case 'Block/Report Spam Opened':
      case 'Message Opened for Blocking':
        fg = dangerColor;
        icon = Icons.block_rounded;
        break;

      case 'Alert Shown':
      case 'Suspicious Voice Alert':
      case 'Alert Shown (Low Confidence)':
        fg = warningColor;
        icon = Icons.warning_amber_rounded;
        break;

      case 'Messages opened':
        fg = successColor;
        icon = Icons.check_circle_rounded;
        break;

      default:
        fg = mutedColor;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
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

  void _showMessageBottomSheet(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    HistoryDetailSheet.show(
      context,
      item: item,
      actionBadge: _actionBadge(item['action']),
      onBlock: () => _openBlockReportSpamFlow(item),
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.delete_outline_rounded, color: dangerColor),
            SizedBox(width: 8),
            Text(
              'Clear History?',
              style: TextStyle(fontWeight: FontWeight.w800, color: inkColor),
            ),
          ],
        ),
        content: const Text(
          'This deletes this account’s history on this phone. It does not delete messages from your SMS app or change blocked senders. This cannot be undone.',
          style: TextStyle(color: mutedColor, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: dangerColor, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final currentPhone = await _getCurrentPhone();

      await DatabaseHelper.instance.clearHistory(userPhone: currentPhone);

      await _loadHistory();
    }
  }

  // ─── Filtered list ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get filteredHistory {
    if (selectedFilter == 1) {
      return history.where((item) => item['category'] == 'Audio').toList();
    }

    if (selectedFilter == 2) {
      return history.where((item) => item['category'] == 'Messages').toList();
    }

    return history;
  }

  // ─── Segmented filter ─────────────────────────────────────────────────────────

  Widget _segmentItem(String text, int index) {
    final selected = selectedFilter == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => selectedFilter = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? surfaceColor : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color.fromRGBO(9, 44, 86, 0.12),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? primaryBlue : mutedColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _segmentedFilter() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: segmentColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _segmentItem('All', 0),
          _segmentItem('Audio', 1),
          _segmentItem('Messages', 2),
        ],
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
            color: mutedColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (count > 0)
          GestureDetector(
            onTap: _confirmClearHistory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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

  // ─── History tile ─────────────────────────────────────────────────────────────

  Widget _riskPill(String risk) {
    final Color tone = risk == 'HIGH'
        ? dangerColor
        : risk == 'MEDIUM'
        ? warningColor
        : risk == 'LOW'
        ? successColor
        : mutedColor;

    final String text = risk == 'HIGH'
        ? 'High risk'
        : risk == 'MEDIUM'
        ? 'Medium risk'
        : risk == 'LOW'
        ? 'Low risk'
        : 'Unknown';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> item) {
    final bool safe = item['safe'];
    final String risk = item['riskLevel'] as String;
    final bool isAudio = item['category'] == 'Audio';

    final Color tone = risk == 'HIGH'
        ? dangerColor
        : risk == 'MEDIUM'
        ? warningColor
        : risk == 'LOW'
        ? successColor
        : mutedColor;

    // Audio shows its label (the stored message is "Voice analysis result: …").
    final String preview = isAudio
        ? (item['result']?.toString() ?? '')
        : (item['message']?.toString() ?? '');

    final double confidenceRaw = item['confidenceRaw'] as double;

    // Audio uses "Confidence".
    // SMS/Message detection uses "Detection Score".
    final String scoreLabel = isAudio ? 'Confidence' : 'Detection score';

    final String scoreText = isAudio
        ? '${confidenceRaw.toStringAsFixed(0)}%'
        : confidenceRaw.toStringAsFixed(0);

    return GestureDetector(
      onTap: () => _showMessageBottomSheet(context, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: _card(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBadge(
                isAudio ? Icons.mic_none_rounded : Icons.sms_outlined,
                tint: risk == 'HIGH' ? dangerColor : accentBlue,
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: inkColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _riskPill(risk),
                      ],
                    ),

                    const SizedBox(height: 2),

                    Text(
                      item['date'],
                      style: const TextStyle(fontSize: 11, color: mutedColor),
                    ),

                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: mutedColor,
                          height: 1.4,
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

                    Text(
                      scoreLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: mutedColor,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (confidenceRaw / 100).clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: borderColor,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                risk == 'UNKNOWN'
                                    ? mutedColor
                                    : (isAudio
                                          ? _confidenceColor(
                                              confidenceRaw,
                                              safe,
                                            )
                                          : tone),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          scoreText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tone,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    _actionBadge(item['action']),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────────

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: _card(
        child: Column(
          children: [
            _iconBadge(Icons.history_rounded, tint: mutedColor),
            const SizedBox(height: 12),
            const Text(
              "No history yet",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: inkColor,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Detected audio and messages will show up here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedColor),
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
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PareHeader(
                title: 'PARE',
                subtitle: 'Detection log',
                username: _username,
              ),

              const SizedBox(height: 16),

              _segmentedFilter(),

              const SizedBox(height: 14),

              _recordCountRow(items.length),

              const SizedBox(height: 10),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadHistory,
                  color: primaryBlue,
                  child: _historyLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _historyError != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _historyError!,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            TextButton(
                              onPressed: _loadHistory,
                              child: const Text('Retry'),
                            ),
                          ],
                        )
                      : items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [_emptyState()],
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
