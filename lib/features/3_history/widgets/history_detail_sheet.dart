import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Redesigned history detail sheet for P.A.R.E.
///
/// Layout (top to bottom):
///   1. Sender header (fixed)
///   2. Verdict card  -> answer first: "Is this safe?" + risk scale + action taken
///   3. Message           -> collapsed to 5 lines, tap to expand, copy button
///   4. Why this result?  -> plain-language explanation
///   5. What you can do   -> only for Medium / High
///   6. Technical details -> collapsed by default (model score, version, keywords)
///   7. Block sender button (fixed at bottom, High-risk SMS only)
class HistoryDetailSheet {
  HistoryDetailSheet._();

  static void show(
    BuildContext context, {
    required Map<String, dynamic> item,
    required Widget actionBadge,
    required VoidCallback onBlock,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _SheetBody(
          item: item,
          controller: controller,
          actionBadge: actionBadge,
          onBlock: onBlock,
        ),
      ),
    );
  }
}

// ─── Design tokens (same as HomeScreen / HistoryScreen) ────────────────────────
const _primaryBlue = Color(0xFF092C56);
const _accentBlue = Color(0xFF2A5298);
const _bg = Color(0xFFF6F8FB);
const _surface = Color(0xFFFFFFFF);
const _border = Color(0xFFE4E9F0);
const _ink = Color(0xFF10192B);
const _muted = Color(0xFF6B7686);
const _success = Color(0xFF1C8756);
const _warning = Color(0xFFB9770E);
const _danger = Color(0xFFC0392B);

// ─── Risk presentation ─────────────────────────────────────────────────────────
class _RiskStyle {
  final Color color;
  final IconData icon;
  final String title;
  final String summary;
  final int level; // 0 low, 1 medium, 2 high

  const _RiskStyle(this.color, this.icon, this.title, this.summary, this.level);

  static _RiskStyle of(String risk, {required bool isAudio}) {
    switch (risk) {
      case 'HIGH':
        return _RiskStyle(
          _danger,
          Icons.gpp_bad_rounded,
          isAudio ? 'Likely synthetic voice' : 'Likely a scam',
          isAudio
              ? 'This voice shows strong signs of being computer-generated.'
              : 'This message contains strong signs of a harmful request.',
          2,
        );
      case 'MEDIUM':
        return _RiskStyle(
          _warning,
          Icons.warning_amber_rounded,
          'Be careful',
          isAudio
              ? 'Some parts of this voice sound artificial.'
              : 'Some patterns look suspicious. Check the sender before you reply.',
          1,
        );
      case 'LOW':
        return _RiskStyle(
          _success,
          Icons.verified_user_rounded,
          'Looks okay',
          isAudio
              ? 'This voice sounds natural.'
              : 'No suspicious request found. This does not prove the sender is genuine.',
          0,
        );
      default:
        return const _RiskStyle(
          _muted,
          Icons.help_outline_rounded,
          'Result unavailable',
          'There is not enough saved information to assess this record.',
          -1,
        );
    }
  }
}

// ─── Sheet body ────────────────────────────────────────────────────────────────
class _SheetBody extends StatefulWidget {
  final Map<String, dynamic> item;
  final ScrollController controller;
  final Widget actionBadge;
  final VoidCallback onBlock;

  const _SheetBody({
    required this.item,
    required this.controller,
    required this.actionBadge,
    required this.onBlock,
  });

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  bool _messageExpanded = false;
  bool _techExpanded = false;

  Map<String, dynamic> get item => widget.item;
  bool get _isAudio => item['category'] == 'Audio';
  String get _message => (item['message'] as String? ?? '').trim();

  @override
  Widget build(BuildContext context) {
    final risk = _RiskStyle.of(
      _isAudio && item['safe'] == true
          ? 'LOW'
          : ((item['riskLevel'] as String?) ?? 'UNKNOWN').toUpperCase(),
      isAudio: _isAudio,
    );
    final showBlock =
        item['category'] == 'Messages' && item['riskLevel'] == 'HIGH';

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              controller: widget.controller,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                _verdictCard(risk),
                if (!_isAudio) ...[const SizedBox(height: 12), _messageCard()],
                const SizedBox(height: 12),
                _whyCard(risk),
                if (risk.level > 0 && !_isAudio) ...[
                  const SizedBox(height: 12),
                  _tipsCard(risk),
                ],
                const SizedBox(height: 12),
                _technicalCard(),
              ],
            ),
          ),
          if (showBlock) _blockBar(),
        ],
      ),
    );
  }

  // ── 1. Header ────────────────────────────────────────────────────────────────
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 14),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: _border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _accentBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isAudio ? Icons.mic_rounded : Icons.sms_rounded,
                  color: _accentBlue,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['type'] ?? ''}  •  ${item['date'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: _muted),
                tooltip: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 2. Verdict card ──────────────────────────────────────────────────────────
  Widget _verdictCard(_RiskStyle risk) {
    final confidenceRaw = (item['confidenceRaw'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: risk.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: risk.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: risk.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(risk.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      risk.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: risk.color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      risk.summary,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _riskScale(risk),
          if (_isAudio) ...[
            const SizedBox(height: 16),
            _audioConfidence(confidenceRaw, risk.color),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'What P.A.R.E. did?',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: widget.actionBadge,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Three segments: Low / Medium / High. Current level is filled.
  Widget _riskScale(_RiskStyle risk) {
    const labels = ['Low', 'Medium', 'High'];
    const colors = [_success, _warning, _danger];

    return Row(
      children: List.generate(3, (i) {
        final active = i == risk.level;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: active ? 10 : 6,
                  decoration: BoxDecoration(
                    color: active
                        ? colors[i]
                        : colors[i].withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? colors[i] : _muted,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _audioConfidence(double percent, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Voice classification score',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ),
            Text(
              item['confidence'] ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: _border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // ── 3. Why this result? ──────────────────────────────────────────────────────
  Widget _whyCard(_RiskStyle risk) {
    final explanation = item['detectionExplanation'] as String?;

    final text = _isAudio
        ? 'Voice analysis estimates whether speech is synthetic. '
              'It cannot tell if a caller is honest or fraudulent.'
        : (explanation != null && explanation.trim().isNotEmpty)
        ? explanation
        : 'This is an older record without a saved breakdown. '
              'The original result has been kept.';

    return _card(
      icon: Icons.lightbulb_outline_rounded,
      title: 'Why this result?',
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, height: 1.55, color: _ink),
      ),
    );
  }

  // ── 4. What you can do ───────────────────────────────────────────────────────
  Widget _tipsCard(_RiskStyle risk) {
    final tips = <String>[
      'Do not tap links or call numbers in this message.',
      'Never share OTPs, passwords, or card details.',
      'Confirm with the company using its official number.',
    ];

    return _card(
      icon: Icons.checklist_rounded,
      title: 'What you can do',
      tint: risk.color,
      child: Column(
        children: tips
            .map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: risk.color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── 5. Message ───────────────────────────────────────────────────────────────
  Widget _messageCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measure =
            TextPainter(
              text: TextSpan(
                text: _message,
                style: const TextStyle(fontSize: 14, height: 1.55),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 5,
            )..layout(
              maxWidth: (constraints.maxWidth - 60).clamp(1.0, double.infinity),
            );
        final isLong = measure.didExceedMaxLines;
        measure.dispose();

        return _card(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Message',
          trailing: _message.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _message));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copy'),
                  style: TextButton.styleFrom(
                    foregroundColor: _accentBlue,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.topCenter,
                  child: Text(
                    _message.isEmpty ? '(No message content)' : _message,
                    maxLines: _messageExpanded ? null : 5,
                    overflow: _messageExpanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: _message.isEmpty ? _muted : _ink,
                    ),
                  ),
                ),
              ),
              if (isLong)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _messageExpanded = !_messageExpanded),
                    style: TextButton.styleFrom(
                      foregroundColor: _accentBlue,
                      padding: const EdgeInsets.only(top: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      _messageExpanded ? 'Show less' : 'Show full message',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── 6. Technical details (collapsed) ─────────────────────────────────────────
  Widget _technicalCard() {
    final modelScore = item['modelScore'] as num?;
    final keywordScore = item['keywordScore'] as int? ?? 0;

    final rows = <MapEntry<String, String>>[
      if (!_isAudio && modelScore != null)
        MapEntry(
          'Model indicator',
          '${(modelScore * 100).toStringAsFixed(1)} / 100',
        ),
      if (!_isAudio && item['modelVersion'] != null)
        MapEntry('Model version', 'SMS model v${item['modelVersion']}'),
      if (!_isAudio)
        MapEntry(
          'Rule evidence score',
          keywordScore == 0
              ? 'None found'
              : '$keywordScore ${keywordScore == 1 ? 'point' : 'points'}',
        ),
      if (_isAudio)
        MapEntry('Confidence', item['confidence']?.toString() ?? '-'),
      MapEntry('Result', item['result']?.toString() ?? '-'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _techExpanded = !_techExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, size: 18, color: _muted),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Technical details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _techExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _techExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: _border),
                  const SizedBox(height: 12),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              r.key,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _muted,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              r.value,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_isAudio)
                    const Text(
                      'The model learned common spam and scam patterns. Its '
                      'score is an indicator, not a confirmed chance of fraud. '
                      'The risk level also depends on whether the message asks '
                      'for something harmful. Rule evidence adds weighted points '
                      'for requests such as sharing an OTP or paying a prize fee. '
                      'These points are not a percentage or a count of scam words.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: _muted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 7. Sticky block bar ──────────────────────────────────────────────────────
  Widget _blockBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            widget.onBlock();
          },
          icon: const Icon(Icons.block_rounded, size: 19),
          label: const Text(
            'Open Messages to block',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _danger,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared card ──────────────────────────────────────────────────────────────
  Widget _card({
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
    Color tint = _primaryBlue,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
