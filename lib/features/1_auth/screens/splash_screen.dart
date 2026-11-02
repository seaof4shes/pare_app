import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pare_app/core/theme/pare_brand.dart';
import 'package:flutter/services.dart';
import 'package:pare_app/core/security/private_preferences.dart';

import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'rings_painter.dart';

/// First screen of the app.
///
/// Types out the tagline, then fades into:
///   - OnboardingScreen on the very first launch
///   - LoginScreen on every launch after that
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const String _tagline = 'Protecting All Random Exchanges...';
  static const Duration _typeSpeed = Duration(milliseconds: 65);
  static const Duration _startDelay = Duration(milliseconds: 600);
  static const Duration _holdAfterTyping = Duration(milliseconds: 800);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  late final Animation<double> _introCurve = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOutCubic,
  );

  late final Future<Widget> _nextScreen = _resolveNext();

  Timer? _typeTimer;
  Timer? _cursorTimer;
  Timer? _startTimer;
  Timer? _navTimer;

  int _chars = 0;
  bool _cursorOn = true;

  @override
  void initState() {
    super.initState();

    _intro.forward();

    _startTimer = Timer(_startDelay, _startTyping);

    _cursorTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() => _cursorOn = !_cursorOn);
    });
  }

  /// Decides where to go next while the tagline is still typing.
  Future<Widget> _resolveNext() async {
    try {
      final prefs = await PrivatePreferences.getInstance();
      final seen = prefs.getBool('onboarding_seen') ?? false;
      return seen ? const LoginScreen() : const OnboardingScreen();
    } catch (_) {
      return const LoginScreen();
    }
  }

  void _startTyping() {
    _typeTimer = Timer.periodic(_typeSpeed, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_chars >= _tagline.length) {
        timer.cancel();
        _navTimer = Timer(_holdAfterTyping, _goNext);
        return;
      }

      setState(() => _chars++);
    });
  }

  Future<void> _goNext() async {
    final next = await _nextScreen;

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => next,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _cursorTimer?.cancel();
    _startTimer?.cancel();
    _navTimer?.cancel();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF092C56), Color(0xFF1E3A9E)],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                right: -110,
                bottom: -110,
                child: CustomPaint(
                  size: Size(340, 340),
                  painter: RingsPainter(),
                ),
              ),

              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _introCurve,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.9,
                          end: 1,
                        ).animate(_introCurve),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              PareBrand.logoAsset,
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                              semanticLabel: 'PARE logo',
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              PareBrand.name,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Typed text + cursor. Untyped characters stay in the
                    // layout (transparent) so the line never shifts sideways.
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                        children: [
                          TextSpan(
                            text: _tagline.substring(0, _chars),
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextSpan(
                            text: '|',
                            style: TextStyle(
                              color: _cursorOn
                                  ? Colors.white
                                  : Colors.transparent,
                            ),
                          ),
                          TextSpan(
                            text: _tagline.substring(_chars),
                            style: const TextStyle(color: Colors.transparent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 48,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      width: 60,
                      height: 3,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 3200),
                        builder: (context, value, child) =>
                            LinearProgressIndicator(
                              value: value,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                      ),
                    ),
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
