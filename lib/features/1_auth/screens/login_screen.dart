import 'package:flutter/material.dart';
import '../../../core/security/login_policy.dart';
import 'package:flutter/services.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pare_app/core/database/user_service.dart';
import 'package:pare_app/features/main_nav_screen.dart';

import 'signup_screen.dart';
import 'otp_screen.dart';
import 'rings_painter.dart';
import 'package:pare_app/features/1_auth/screens/forgot_mpin_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool unlockMode;

  const LoginScreen({super.key, this.unlockMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();

  bool _autoValidate = false;
  bool _isSendingOtp = false;
  bool _obscurePin = true;
  bool _returningAccount = false;
  String _username = '';

  // Design tokens
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color heroBlue = Color(0xFF14437F);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color sheetColor = Color(0xFFEEF2F7);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color dangerColor = Color(0xFFC0392B);

  @override
  void initState() {
    super.initState();
    _prefillAccount();
  }

  Future<void> _prefillAccount() async {
    try {
      final prefs = await PrivatePreferences.getInstance();
      final phone = prefs.getString('phone') ?? '';
      if (phone.isEmpty) return;
      final trusted = !requiresLoginOtp(
        localAccountExists: await UserService().phoneExists(phone),
        phone: phone,
        authenticatedPhone: FirebaseAuth.instance.currentUser?.phoneNumber,
        verificationRequired: prefs.getBool('requireOtp') ?? false,
      );
      if (mounted) {
        // The field shows "+63" already, so only the 10 digits go inside.
        _phoneController.text = phone.startsWith('+63')
            ? phone.substring(3)
            : phone;
        setState(() {
          _returningAccount = trusted;
          _username = prefs.getString('username') ?? '';
        });
      }
    } catch (_) {
      // Keep account entry available if protected profile loading fails.
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Accepts "9XXXXXXXXX" or "09XXXXXXXXX" and returns "09XXXXXXXXX".
  String _normalizePhone(String v) {
    if (v.length == 10 && v.startsWith('9')) return '0$v';
    return v;
  }

  String _formatPhone(String rawPhone) {
    return rawPhone.startsWith('0')
        ? '+63${rawPhone.substring(1)}'
        : '+63$rawPhone';
  }

  void _useAnotherAccount() {
    setState(() {
      _returningAccount = false;
      _phoneController.clear();
      _pinController.clear();
    });
  }

  // ─── Login logic (unchanged behavior) ──────────────────────────────────────

  Future<void> _onLogin() async {
    if (_isSendingOtp) return;
    setState(() => _autoValidate = true);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final rawPhone = _normalizePhone(_phoneController.text.trim());
    final pin = _pinController.text.trim();

    if (!rawPhone.startsWith('09')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Phone number must start with 09")),
      );
      return;
    }

    final phone = _formatPhone(rawPhone);

    setState(() => _isSendingOtp = true);

    try {
      final userService = UserService();
      final prefs = await PrivatePreferences.getInstance();

      // 1. CHECK LOCAL ACCOUNT
      final localAccountExists = await userService.phoneExists(phone);

      // 2. FRESH INSTALL / LOCAL ACCOUNT MISSING
      // Do NOT query Firestore here: Firebase Phone Auth must finish first.
      // OtpScreen restores the account from Firestore after OTP success.
      if (!localAccountExists) {
        await prefs.setString('pending_login_phone', phone);
        await prefs.setBool('isLoggedIn', false);

        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,

          verificationCompleted: (PhoneAuthCredential credential) async {
            try {
              await FirebaseAuth.instance.signInWithCredential(credential);
              if (FirebaseAuth.instance.currentUser?.phoneNumber != phone) {
                throw StateError(
                  'Phone verification did not match this account',
                );
              }

              final restored = await userService
                  .restoreCurrentUserFromFirestore(mpin: pin);

              if (!restored) {
                throw Exception(
                  "Unable to restore the P.A.R.E. account from Firebase.",
                );
              }

              final localUser = await userService.getUserByPhone(phone);

              await prefs.setString('phone', phone);

              await prefs.setString(
                'username',
                localUser?['username']?.toString() ?? 'User',
              );

              await prefs.setBool('requireOtp', false);
              await prefs.setBool('isLoggedIn', true);

              if (!mounted) return;

              setState(() => _isSendingOtp = false);

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MainNavScreen()),
              );
            } catch (e) {
              if (!mounted) return;

              setState(() => _isSendingOtp = false);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Account restoration failed: $e")),
              );
            }
          },

          verificationFailed: (FirebaseAuthException e) {
            if (!mounted) return;

            setState(() => _isSendingOtp = false);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Unable to send OTP: ${e.message ?? e.code}"),
              ),
            );
          },

          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;

            setState(() => _isSendingOtp = false);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtpScreen(
                  phone: phone,
                  verificationId: verificationId,
                  isSignUp: false,
                  isLogin: true,
                  pin: pin,
                ),
              ),
            );
          },

          codeAutoRetrievalTimeout: (String verificationId) {
            // OtpScreen handles manual OTP entry.
          },
        );

        return;
      }

      // 3. LOCAL ACCOUNT EXISTS -> existing-device login with local MPIN
      final success = await userService.loginUser(
        usernameOrPhone: phone,
        mpin: pin,
      );

      if (!success) {
        final isLocked = await userService.isMpinLocked(phone);

        if (!mounted) return;

        setState(() => _isSendingOtp = false);

        if (isLocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Too many incorrect PIN attempts. Please try again later.",
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Incorrect PIN")));
        }

        return;
      }

      // 4. CHECK WHETHER OTP IS REQUIRED
      final requireOtp = requiresLoginOtp(
        localAccountExists: localAccountExists,
        phone: phone,
        authenticatedPhone: FirebaseAuth.instance.currentUser?.phoneNumber,
        verificationRequired: prefs.getBool('requireOtp') ?? false,
      );

      // 5. NORMAL LOGIN
      if (!requireOtp) {
        final user = await userService.getUserByPhone(phone);

        if (!mounted) return;

        await prefs.setString('phone', phone);

        await prefs.setString(
          'username',
          user?['username']?.toString() ?? 'User',
        );

        await prefs.setBool('isLoggedIn', true);

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavScreen()),
        );

        return;
      }

      // 6. EXISTING DEVICE LOGIN -> REQUIRE OTP
      await prefs.setString('pending_login_phone', phone);
      await prefs.setBool('isLoggedIn', false);

      // 7. SEND FIREBASE OTP
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,

        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (FirebaseAuth.instance.currentUser?.phoneNumber != phone) {
              throw StateError('Phone verification did not match this account');
            }

            final user = await userService.getUserByPhone(phone);

            await prefs.setBool('requireOtp', false);
            await prefs.setBool('isLoggedIn', true);
            await prefs.setString('phone', phone);

            await prefs.setString(
              'username',
              user?['username']?.toString() ?? 'User',
            );

            if (!mounted) return;

            setState(() => _isSendingOtp = false);

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const MainNavScreen()),
            );
          } catch (e) {
            if (!mounted) return;

            setState(() => _isSendingOtp = false);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Automatic verification failed: $e")),
            );
          }
        },

        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;

          setState(() => _isSendingOtp = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Unable to send OTP: ${e.message ?? e.code}"),
            ),
          );
        },

        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          setState(() => _isSendingOtp = false);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpScreen(
                phone: phone,
                verificationId: verificationId,
                isSignUp: false,
                isLogin: true,
                pin: pin,
              ),
            ),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          // OtpScreen handles the OTP entry.
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSendingOtp = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Login error: $e")));
    }
  }

  // ─── UI pieces ─────────────────────────────────────────────────────────────

  Widget _hero(double height) {
    final title = _returningAccount ? 'Welcome back!' : 'Hello!';
    final subtitle = _returningAccount
        ? (_username.isNotEmpty
              ? 'Hi $_username, enter your MPIN'
              : 'Enter your MPIN to unlock')
        : 'Welcome to P.A.R.E';

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
              left: 26,
              bottom: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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

  InputDecoration _pillDecoration({
    required String hint,
    required Widget prefix,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(30),
      borderSide: BorderSide(color: color, width: width),
    );

    return InputDecoration(
      counterText: '',
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 18, right: 10),
        child: prefix,
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: suffix,
      enabledBorder: border(Colors.transparent, 1),
      focusedBorder: border(accentBlue, 1.4),
      errorBorder: border(dangerColor, 1),
      focusedErrorBorder: border(dangerColor, 1.4),
      errorStyle: const TextStyle(fontSize: 12, color: dangerColor),
    );
  }

  Widget _phoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.number,
      maxLength: 11,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: inkColor,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: _pillDecoration(
        hint: '9XX XXX XXXX',
        prefix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.phone_iphone_rounded, size: 19, color: mutedColor),
            const SizedBox(width: 8),
            const Text(
              '+63',
              style: TextStyle(
                color: inkColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 20, color: const Color(0xFFE4E9F0)),
          ],
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Phone number is required';

        final n = _normalizePhone(v);

        if (n.length != 11) return 'Please enter your 10-digit number';
        if (!n.startsWith('09')) return 'Must start with 9';

        return null;
      },
    );
  }

  Widget _pinField() {
    return TextFormField(
      controller: _pinController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      obscureText: _obscurePin,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: inkColor,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 2,
      ),
      decoration: _pillDecoration(
        hint: '6-digit MPIN',
        prefix: const Icon(
          Icons.lock_outline_rounded,
          size: 19,
          color: mutedColor,
        ),
        suffix: IconButton(
          onPressed: () => setState(() => _obscurePin = !_obscurePin),
          icon: Icon(
            _obscurePin
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 19,
            color: mutedColor,
          ),
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'PIN is required';
        if (v.length != 6) return 'PIN must be exactly 6 digits';
        return null;
      },
    );
  }

  Widget _loginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSendingOtp ? null : _onLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          elevation: 4,
          shadowColor: const Color.fromRGBO(9, 44, 86, 0.35),
          shape: const StadiumBorder(),
        ),
        child: _isSendingOtp
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                _returningAccount ? 'Unlock' : 'Login',
                style: const TextStyle(
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

    final heroHeight = media.padding.top + 260;
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
                child: _hero(heroHeight),
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
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _autoValidate
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _returningAccount ? 'Unlock' : 'Login',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: primaryBlue,
                            ),
                          ),

                          const SizedBox(height: 22),

                          if (!_returningAccount) ...[
                            _phoneField(),
                            const SizedBox(height: 14),
                          ],

                          _pinField(),

                          const SizedBox(height: 6),

                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ForgotMpinScreen(),
                                  ),
                                );
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'Forgot MPIN?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: accentBlue,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          _loginButton(),

                          const SizedBox(height: 22),

                          Center(
                            child: _returningAccount
                                ? GestureDetector(
                                    onTap: _isSendingOtp
                                        ? null
                                        : _useAnotherAccount,
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: mutedColor,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: _username.isNotEmpty
                                                ? 'Not $_username? '
                                                : 'Not you? ',
                                          ),
                                          const TextSpan(
                                            text: 'Use another account',
                                            style: TextStyle(
                                              color: primaryBlue,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const SignUpScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: mutedColor,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: "Don't have an account? ",
                                          ),
                                          TextSpan(
                                            text: 'Sign Up',
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
              ),

              // Shield illustration sitting on the sheet edge
              // (this is the "plant" from the reference design).
              Positioned(
                top: sheetTop - 108,
                right: 28,
                child: const CustomPaint(
                  size: Size(96, 130),
                  painter: _ShieldPainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple two-tone shield with a check mark and a soft ground shadow.
class _ShieldPainter extends CustomPainter {
  const _ShieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - 12; // leave room for the shadow

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, h + 7),
        width: w * 0.85,
        height: 10,
      ),
      Paint()..color = const Color(0x22092C56),
    );

    final shield = Path()
      ..moveTo(w * 0.5, 0)
      ..cubicTo(w * 0.65, h * 0.10, w * 0.85, h * 0.14, w, h * 0.14)
      ..cubicTo(w, h * 0.60, w * 0.78, h * 0.85, w * 0.5, h)
      ..cubicTo(w * 0.22, h * 0.85, 0, h * 0.60, 0, h * 0.14)
      ..cubicTo(w * 0.15, h * 0.14, w * 0.35, h * 0.10, w * 0.5, 0)
      ..close();

    // Right half (darker)
    canvas.drawPath(shield, Paint()..color = const Color(0xFF2A5298));

    // Left half (lighter) for the two-tone look
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w / 2, h));
    canvas.drawPath(shield, Paint()..color = const Color(0xFF5B8DD6));
    canvas.restore();

    // Check mark
    final check = Path()
      ..moveTo(w * 0.27, h * 0.50)
      ..lineTo(w * 0.44, h * 0.66)
      ..lineTo(w * 0.74, h * 0.36);

    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
