import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/security/local_crypto_service.dart';

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
  // Design tokens — mirrored from HomeScreen so both screens read as one
  // cohesive design system.
  // ---------------------------------------------------------------------
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E9F0);
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
    // Nothing needed here for the block flow.
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
    final prefs = await SharedPreferences.getInstance();
    final savedUsername = prefs.getString('username') ?? "Username";

    if (!mounted) return;

    setState(() {
      _username = savedUsername;
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final currentPhone = prefs.getString('phone') ?? '';

    final loadedHistory = await DatabaseHelper.instance.getHistory(
      userPhone: currentPhone,
    );

    if (!mounted) return;

    final decryptedHistory = <Map<String, dynamic>>[];

    for (final data in loadedHistory) {
      final mutable = Map<String, dynamic>.from(data);

      mutable['message'] = await LocalCryptoService.instance.decryptText(
        mutable['message']?.toString() ?? '',
      );

      decryptedHistory.add(mutable);
    }

    final convertedHistory = decryptedHistory.map((data) {
      final confidenceValue = ((data['confidence'] as num?)?.toDouble() ?? 0.0);

      final isCall = (data['category'] ?? '') == 'Audio';

      final confidencePercent = isCall
          ? confidenceValue
          : confidenceValue * 100;

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
        'senderNumber': data['senderNumber']?.toString() ?? '',
        'type': data['type'] ?? 'SMS Message',
        'message': data['message'] ?? '',
        'date': _formatDate(data['dateTime']),
        'result': data['result'] ?? 'Unknown',
        'confidenceRaw': confidencePercent,
        'confidence': '${confidencePercent.toStringAsFixed(2)}%',
        'riskLevel': riskLevel,
        'keywordScore': keywordScore,
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
          'P.A.R.E. will open your messaging app '
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
      // Save that P.A.R.E. opened the messaging app
      // for the user to manually block the sender.
      await DatabaseHelper.instance.updateHistoryAction(
        historyId: historyId,
        action: 'Message Opened for Blocking',
        userPhone: await _getCurrentPhone(),
      );

      await _loadHistory();

      // Open the sender's SMS conversation.
      await _blockChannel.invokeMethod('openSmsConversation', {
        'sender': senderNumber,
      });
    } on PlatformException catch (e) {
      debugPrint(
        '❌ Block flow error: '
        '${e.code} - ${e.message}',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'Unable to open the messaging application.',
          ),
        ),
      );
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('phone') ?? '';
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
    if (safe) return successColor;
    if (percent >= 75) return dangerColor;
    if (percent >= 40) return warningColor;
    return successColor;
  }

  // ─── Shared UI pieces (mirrored from HomeScreen) ──────────────────────────────

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

  Widget _divider() => Divider(height: 1, thickness: 1, color: borderColor);

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
      case 'Sender Blocked':
        fg = successColor;
        icon = Icons.check_circle_rounded;
        break;
      default:
        fg = successColor;
        icon = Icons.check_circle_outline_rounded;
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

  // ─── Risk level badge (shown only in bottom sheet) ────────────────────────────

  Widget _riskBadge(String riskLevel) {
    Color fg;
    String label;

    switch (riskLevel) {
      case 'HIGH':
        fg = dangerColor;
        label = 'High Risk';
        break;
      case 'MEDIUM':
        fg = warningColor;
        label = 'Medium Risk';
        break;
      default:
        fg = successColor;
        label = 'Low Risk';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.10),
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
                color: mutedColor,
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
            color: surfaceColor,
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
                    color: borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Sender row
              Row(
                children: [
                  _iconBadge(
                    item['category'] == 'Audio'
                        ? Icons.phone_rounded
                        : Icons.sms_rounded,
                    tint: accentBlue,
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
                            color: inkColor,
                          ),
                        ),
                        Text(
                          item['date'],
                          style: const TextStyle(
                            fontSize: 12,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _divider(),
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
                          color: mutedColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          (item['message'] as String).isNotEmpty
                              ? item['message']
                              : '(No message content)',
                          style: const TextStyle(
                            fontSize: 14,
                            color: inkColor,
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
                          color: mutedColor,
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
                              color: safe ? successColor : dangerColor,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              item['result'],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: safe ? successColor : dangerColor,
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
                                backgroundColor: borderColor,
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
                            color: inkColor,
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
                            color: inkColor,
                          ),
                        ),
                      ),

                      if (item['category'] == 'Messages' &&
                          item['riskLevel'] == 'HIGH') ...[
                        const SizedBox(height: 12),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: dangerColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: dangerColor.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: dangerColor,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'High-Risk Message',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: dangerColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 7),

                              const Text(
                                'You can block or report this sender through '
                                'your messaging app.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: mutedColor,
                                  height: 1.4,
                                ),
                              ),

                              const SizedBox(height: 12),

                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _openBlockReportSpamFlow(item);
                                  },
                                  icon: const Icon(
                                    Icons.block_rounded,
                                    size: 19,
                                  ),
                                  label: const Text(
                                    'BLOCK SENDER',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: dangerColor,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

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
          'This will permanently delete all scam detection records. '
          'This action cannot be undone.',
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

  // ─── Filter tabs ──────────────────────────────────────────────────────────────

  Widget _filterButton(String text, int index) {
    final selected = selectedFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => selectedFilter = index),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: selected ? primaryBlue : surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? primaryBlue : borderColor),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : inkColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
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

  // ─── History tile — now a bordered surface card, matching Home's _card ───────

  Widget _historyTile(Map<String, dynamic> item) {
    final bool safe = item['safe'];
    final String message = item['message'] ?? '';
    final double confidenceRaw = item['confidenceRaw'] as double;
    final bool isLong = message.length > 80;

    return GestureDetector(
      onTap: () => _showMessageBottomSheet(context, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: _card(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _iconBadge(
                  item['category'] == 'Audio' ? Icons.phone : Icons.sms,
                  tint: accentBlue,
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
                              color: inkColor,
                            ),
                          ),
                        ),
                        Icon(
                          safe
                              ? Icons.check_circle_outline
                              : Icons.warning_amber_rounded,
                          size: 14,
                          color: safe ? successColor : dangerColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item['result'],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: safe ? successColor : dangerColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Date
                    Text(
                      item['date'],
                      style: const TextStyle(fontSize: 11, color: mutedColor),
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
                                color: mutedColor,
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
                              backgroundColor: borderColor,
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
      ),
    );
  }

  // ─── Empty state — styled like Home's status card ────────────────────────────

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
              _header(),
              const SizedBox(height: 18),
              Row(
                children: [
                  _filterButton("All", 0),
                  const SizedBox(width: 8),
                  _filterButton("Audio", 1),
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
                  color: primaryBlue,
                  child: items.isEmpty
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
