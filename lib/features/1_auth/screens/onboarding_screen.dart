import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pare_app/core/security/private_preferences.dart';

import 'login_screen.dart';

/// Three animated intro slides, shown only on the first launch.
/// Finishing (or skipping) saves `onboarding_seen = true`.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color mutedColor = Color(0xFF6B7686);

  static const List<_SlideData> _slides = [
    _SlideData(
      title: 'Check suspicious messages',
      body:
          'P.A.R.E. checks texts for suspicious requests and explains the risk. Low risk does not verify the sender.',
    ),
    _SlideData(
      title: 'Check voice recordings',
      body:
          'Check recordings for AI-made speech before you trust the person on the line.',
    ),
    _SlideData(
      title: 'Private and in your control',
      body:
          'Enable the checks you want, review encrypted history, and manage alerts in Settings.',
    ),
  ];

  final PageController _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }

    _controller.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    try {
      final prefs = await PrivatePreferences.getInstance();
      await prefs.setBool('onboarding_seen', true);
    } catch (_) {
      // If saving fails, onboarding simply shows again next launch.
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _Slide(kind: i, active: i == _index, data: _slides[i]),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final active = i == _index;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 24 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: active ? primaryBlue : const Color(0xFFCBD5E3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: const Color.fromRGBO(9, 44, 86, 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLast ? 'Get started' : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideData {
  final String title;
  final String body;

  const _SlideData({required this.title, required this.body});
}

// ─────────────────────────────────────────────────────────────────────────────
// One slide: animated illustration + title + description.
// The animation replays every time the slide becomes the active page.
// ─────────────────────────────────────────────────────────────────────────────

class _Slide extends StatefulWidget {
  final int kind; // 0 = scam text, 1 = voice, 2 = privacy
  final bool active;
  final _SlideData data;

  const _Slide({required this.kind, required this.active, required this.data});

  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> with TickerProviderStateMixin {
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color inkColor = Color(0xFF10192B);
  static const Color dangerColor = Color(0xFFC0392B);
  static const Color successColor = Color(0xFF1C8756);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _play();
  }

  void _play() {
    _intro.forward(from: 0);
    _loop.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Slide oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.active && !oldWidget.active) {
      _play();
    } else if (!widget.active && oldWidget.active) {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Progress (0..1) of [t] between [a] and [b].
  double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 270,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFE4ECF8), Color(0xFFF1F5FB)],
              ),
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_intro, _loop]),
                builder: (context, child) {
                  switch (widget.kind) {
                    case 0:
                      return _scamArt();
                    case 1:
                      return _voiceArt();
                    default:
                      return _privacyArt();
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 26),

          Text(
            widget.data.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: primaryBlue,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            widget.data.body,
            style: const TextStyle(
              fontSize: 14,
              color: mutedColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Slide 1: scam text being scanned ────────────────────────────────────────
  Widget _scamArt() {
    final t = _intro.value;

    final scan = _seg(t, 0.0, 0.45);
    final h1 = Curves.easeOut.transform(_seg(t, 0.20, 0.35));
    final h2 = Curves.easeOut.transform(_seg(t, 0.32, 0.47));
    final h3 = Curves.easeOut.transform(_seg(t, 0.44, 0.59));
    final badge = Curves.easeOutBack.transform(_seg(t, 0.62, 0.82));

    TextStyle hl(double p) => TextStyle(
      backgroundColor: Color.lerp(
        Colors.transparent,
        const Color(0xFFFBE3A6),
        p,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 236,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(9, 44, 86, 0.12),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '+63 917 555 0199',
                      style: TextStyle(fontSize: 11, color: mutedColor),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 13,
                          color: inkColor,
                          height: 1.45,
                        ),
                        children: [
                          const TextSpan(text: 'Your GCash account is '),
                          TextSpan(text: 'suspended', style: hl(h1)),
                          const TextSpan(text: '. '),
                          TextSpan(text: 'Verify now', style: hl(h2)),
                          const TextSpan(text: ' at '),
                          TextSpan(text: 'bit.ly/g-verify', style: hl(h3)),
                          const TextSpan(text: ' to avoid closure.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Scan line sweeping down the message.
              Positioned(
                left: 0,
                right: 0,
                top: -26 + scan * 150,
                child: Opacity(
                  opacity: (scan > 0 && scan < 1) ? 1 : 0,
                  child: Container(
                    height: 26,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x002A5298), Color(0x382A5298)],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Opacity(
          opacity: badge.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.8 + 0.2 * badge,
            child: _pill(
              icon: Icons.warning_amber_rounded,
              text: "High risk, don't tap links",
              color: dangerColor,
            ),
          ),
        ),
      ],
    );
  }

  // ── Slide 2: voice waveform + synthetic meter ───────────────────────────────
  Widget _voiceArt() {
    final t = _intro.value;
    final meter = Curves.easeOut.transform(_seg(t, 0.15, 0.80));
    final badge = Curves.easeOutBack.transform(_seg(t, 0.75, 0.95));

    const heights = [
      18.0, 34, 52, 26, 64, 40, 72, 30, 58, 44, //
      70, 36, 60, 28, 50, 66, 32, 54, 24, 46,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 84,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(heights.length, (i) {
              final wave =
                  0.5 + 0.5 * math.sin(2 * math.pi * (_loop.value + i * 0.07));
              final h = 10 + (heights[i] - 10) * wave;

              return Container(
                width: 5,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: accentBlue,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: 226,
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Synthetic voice',
                    style: TextStyle(fontSize: 11, color: mutedColor),
                  ),
                  Text(
                    '91%',
                    style: TextStyle(
                      fontSize: 11,
                      color: dangerColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Container(
                  height: 8,
                  color: const Color(0xFFD9E2F0),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: 0.91 * meter,
                    child: Container(color: dangerColor),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Opacity(
          opacity: badge.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.8 + 0.2 * badge,
            child: _pill(
              icon: Icons.graphic_eq_rounded,
              text: 'Likely synthetic voice',
              color: dangerColor,
            ),
          ),
        ),
      ],
    );
  }

  // ── Slide 3: privacy shield + benefit chips ─────────────────────────────────
  Widget _privacyArt() {
    final t = _intro.value;
    final pulse = _loop.value;

    const chips = [
      'Records encrypted on your device',
      'Block risky senders in one tap',
      'Full history, always reviewable',
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 92 + 40 * pulse,
              height: 92 + 40 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryBlue.withValues(alpha: 0.07 * (1 - pulse)),
              ),
            ),
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: primaryBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        ...List.generate(chips.length, (i) {
          final p = Curves.easeOut.transform(
            _seg(t, 0.15 + i * 0.2, 0.40 + i * 0.2),
          );

          return Opacity(
            opacity: p,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - p)),
              child: Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(9, 44, 86, 0.08),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: successColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      chips[i],
                      style: const TextStyle(fontSize: 12, color: inkColor),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
