import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pare_app/core/security/private_preferences.dart';

import 'package:pare_app/core/database/user_service.dart';
import 'package:pare_app/features/main_nav_screen.dart';

import 'rings_painter.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String verificationId;
  final bool isSignUp;
  final bool isLogin;
  final String? username;
  final String? pin;
  final FirebaseAuth? auth;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.verificationId,
    this.isSignUp = false,
    this.isLogin = false,
    this.username,
    this.pin,
    this.auth,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _timer;

  int _secondsLeft = 0;
  bool _canResend = true;
  bool _isVerifying = false;
  bool _isResending = false;
  int? _resendToken;

  late String _verificationId;

  // Design tokens (same as LoginScreen)
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color heroBlue = Color(0xFF14437F);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color sheetColor = Color(0xFFEEF2F7);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);

  String get _otp => _controllers.map((e) => e.text).join();
  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;

  String get _maskedPhone {
    final p = widget.phone;

    if (p.length < 8) {
      return p;
    }

    return "${p.substring(0, 4)}*****${p.substring(p.length - 4)}";
  }

  @override
  void initState() {
    super.initState();

    _verificationId = widget.verificationId;
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }

    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }

    _timer?.cancel();

    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();

    setState(() {
      _secondsLeft = 30;
      _canResend = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsLeft <= 1) {
        timer.cancel();

        setState(() {
          _canResend = true;
          _secondsLeft = 0;
        });
      } else {
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  void _clearOtpFields() {
    for (final controller in _controllers) {
      controller.clear();
    }

    FocusScope.of(context).unfocus();

    _focusNodes[0].requestFocus();
  }

  /// Creates the local account only during signup.
  ///
  /// The MPIN is stored locally as a hash.
  /// The MPIN is NOT stored in Firestore.
  Future<void> _saveUserIfSignUp() async {
    if (!widget.isSignUp) {
      return;
    }

    await UserService().syncUserToFirestore(
      username: widget.username ?? '',
      phoneNumber: widget.phone,
      mpin: widget.pin ?? '',
    );
  }

  /// Restores the local account after a successful OTP login
  /// when the app has been reinstalled and the local SQLite
  /// account no longer exists.
  ///
  /// IMPORTANT:
  /// The MPIN is NOT being verified against Firestore.
  /// Firebase OTP verifies ownership of the phone number.
  /// The entered MPIN is then established again as the
  /// device-local MPIN.
  Future<void> _restoreUserIfFreshLogin() async {
    if (!widget.isLogin) {
      return;
    }

    final userService = UserService();

    // Check whether the account already exists locally.
    final localUser = await userService.getUserByPhone(widget.phone);

    if (localUser != null) {
      // Normal login on an existing installation.
      return;
    }

    // Fresh installation: Firebase account should already exist.
    final firebaseUser = _auth.currentUser;

    if (firebaseUser == null) {
      throw Exception('Firebase authentication was not completed.');
    }

    final pin = widget.pin;

    if (pin == null || pin.isEmpty) {
      throw Exception(
        'MPIN is required to restore the account on this device.',
      );
    }

    final restored = await userService.restoreCurrentUserFromFirestore(
      mpin: pin,
    );

    if (!restored) {
      throw Exception('Unable to restore the PARE account from Firebase.');
    }
  }

  /// Completes the local session after successful OTP verification.
  Future<void> _completeAuthentication() async {
    if (_auth.currentUser?.phoneNumber != widget.phone) {
      throw StateError('Phone verification does not match this account');
    }
    final prefs = await PrivatePreferences.getInstance();

    await prefs.setString('phone', widget.phone);

    String username = widget.username ?? 'User';

    if (widget.isLogin) {
      final localUser = await UserService().getUserByPhone(widget.phone);

      username = localUser?['username']?.toString() ?? 'User';
    }

    await prefs.setString('username', username);

    // OTP has been successfully completed.
    await prefs.setBool('requireOtp', false);
    await prefs.setBool('isLoggedIn', true);
  }

  Future<void> _goToHome() async {
    if (!mounted) {
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MainNavScreen()),
      (_) => false,
    );
  }

  Future<void> _handleAutomaticVerification(
    PhoneAuthCredential credential,
  ) async {
    if (_isVerifying || !mounted) return;
    setState(() {
      _isVerifying = true;
      _isResending = false;
    });
    try {
      await _auth.signInWithCredential(credential);

      // Signup creates the account normally.
      await _saveUserIfSignUp();

      // Fresh login after reinstall restores the local account.
      await _restoreUserIfFreshLogin();

      await _completeAuthentication();

      await _goToHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Automatic verification failed')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resendOtp() async {
    if (!_canResend || _isResending || _isVerifying) {
      return;
    }

    _clearOtpFields();
    setState(() => _isResending = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phone,
        forceResendingToken: _resendToken,

        verificationCompleted: (PhoneAuthCredential credential) async {
          await _handleAutomaticVerification(credential);
        },

        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) {
            return;
          }
          setState(() => _isResending = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: ${e.message ?? 'Failed to resend OTP'}"),
            ),
          );
        },

        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;

          if (!mounted) {
            return;
          }

          _startTimer();
          setState(() => _isResending = false);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("OTP resent successfully")),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isResending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not request another code. Please try again.'),
        ),
      );
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp;

    if (code.length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter 6-digit OTP")));

      return;
    }

    if (_isVerifying || _isResending) {
      return;
    }

    setState(() {
      _isVerifying = true;
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: code,
      );

      // Firebase verifies the phone number.
      await _auth.signInWithCredential(credential);

      // Signup flow remains unchanged.
      await _saveUserIfSignUp();

      // If this is a login after reinstall, restore the
      // account locally after Firebase OTP succeeds.
      await _restoreUserIfFreshLogin();

      // Save the authenticated local session.
      await _completeAuthentication();

      // Go to Home.
      await _goToHome();
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? "Invalid OTP")));
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVerifying = false;
        });
      }
    }
  }

  // ─── OTP box input (with paste support) ────────────────────────────────────

  /// Handles typing, deleting and pasting in box [i].
  ///
  /// More than one digit arriving at once (a paste, or typing over a filled
  /// box) is spread across this box and the ones after it.
  void _onBoxChanged(int i, String value) {
    if (value.isEmpty) {
      if (i > 0) _focusNodes[i - 1].requestFocus();
      return;
    }

    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      _controllers[i].clear();
      return;
    }

    var last = i;

    for (var j = 0; j < digits.length && i + j < 6; j++) {
      last = i + j;
      _controllers[last].value = TextEditingValue(
        text: digits[j],
        selection: const TextSelection.collapsed(offset: 1),
      );
    }

    if (last < 5) {
      _focusNodes[last + 1].requestFocus();
    } else {
      _focusNodes[5].requestFocus();
    }

    setState(() {});
  }

  Widget _otpBox(int i) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );

    return SizedBox(
      height: 54,
      child: TextField(
        controller: _controllers[i],
        focusNode: _focusNodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        cursorColor: primaryBlue,
        style: const TextStyle(
          color: inkColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          enabledBorder: border(Colors.transparent, 1),
          focusedBorder: border(accentBlue, 1.4),
        ),
        onTap: () {
          // Select the digit so typing replaces it.
          final c = _controllers[i];
          c.selection = TextSelection(
            baseOffset: 0,
            extentOffset: c.text.length,
          );
        },
        onChanged: (value) => _onBoxChanged(i, value),
      ),
    );
  }

  // ─── UI pieces ─────────────────────────────────────────────────────────────

  Widget _hero(double height, double topInset) {
    return ClipRect(
      child: Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryBlue, heroBlue],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              left: -80,
              top: -80,
              child: CustomPaint(size: Size(240, 240), painter: RingsPainter()),
            ),
            Positioned(
              left: 16,
              top: topInset + 10,
              child: Material(
                color: const Color.fromRGBO(255, 255, 255, 0.14),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _isVerifying ? null : () => Navigator.pop(context),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 26,
              right: 26,
              bottom: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verify your number',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter the 6-digit code sent to $_maskedPhone',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
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

  Widget _resendRow() {
    final active = _canResend && !_isResending && !_isVerifying;

    return Center(
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 13, color: mutedColor),
          children: [
            const TextSpan(text: "Didn’t receive it? "),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: active ? _resendOtp : null,
                child: Text(
                  _isResending
                      ? 'Sending…'
                      : _canResend
                      ? 'Resend OTP'
                      : '${_secondsLeft}s',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _canResend && !_isResending
                        ? accentBlue
                        : const Color(0xFF9AA4B2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verifyButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isVerifying || _isResending ? null : _verifyOtp,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          elevation: 4,
          shadowColor: const Color.fromRGBO(9, 44, 86, 0.35),
          shape: const StadiumBorder(),
        ),
        child: _isVerifying
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Text(
                'Verify OTP',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    final heroHeight = media.padding.top + 240;
    final sheetTop = heroHeight - 40;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: sheetColor,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: heroHeight,
                child: _hero(heroHeight, media.padding.top),
              ),

              // Rounded sheet with the form.
              Padding(
                padding: EdgeInsets.only(top: sheetTop),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: media.size.height - sheetTop,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      26,
                      30,
                      26,
                      24 + media.padding.bottom,
                    ),
                    decoration: const BoxDecoration(
                      color: sheetColor,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(36),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verification',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: primaryBlue,
                          ),
                        ),

                        const SizedBox(height: 22),

                        Row(
                          children: List.generate(6, (i) {
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                                child: _otpBox(i),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 18),

                        _resendRow(),

                        const SizedBox(height: 20),

                        _verifyButton(),

                        const SizedBox(height: 22),

                        Center(
                          child: GestureDetector(
                            onTap: _isVerifying
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: mutedColor,
                                ),
                                children: [
                                  TextSpan(text: 'Wrong number? '),
                                  TextSpan(
                                    text: 'Change it',
                                    style: TextStyle(
                                      color: primaryBlue,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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