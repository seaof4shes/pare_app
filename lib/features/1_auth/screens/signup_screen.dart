import '../widgets/auth_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pare_app/core/database/user_service.dart';

import 'login_screen.dart';
import 'otp_screen.dart';
import 'rings_painter.dart';

// Design tokens (same as LoginScreen)
const Color _primaryBlue = Color(0xFF092C56);
const Color _heroBlue = Color(0xFF14437F);
const Color _accentBlue = Color(0xFF2A5298);
const Color _sheetColor = Color(0xFFEEF2F7);
const Color _inkColor = Color(0xFF10192B);
const Color _mutedColor = Color(0xFF6B7686);
const Color _dangerColor = Color(0xFFC0392B);

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();

  // Errors that come from async checks (username taken, number registered).
  String? _usernameServerError;
  String? _phoneServerError;
  String? _termsError;

  bool _autoValidate = false;
  bool _agreed = false;
  bool _hasViewedTerms = false;
  bool _isSendingOtp = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
    _pin.dispose();
    _confirmPin.dispose();
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Sign up logic ─────────────────────────────────────────────────────────

  Future<void> _createAccount() async {
    if (_isSendingOtp) return;

    setState(() {
      _autoValidate = true;
      _usernameServerError = null;
      _phoneServerError = null;
      _termsError = null;
    });

    final fieldsValid = _formKey.currentState!.validate();

    if (!_agreed) {
      setState(() {
        _termsError = !_hasViewedTerms
            ? "Please read the Terms and Conditions first"
            : "You must agree to the Terms and Conditions";
      });
    }

    if (!fieldsValid || !_agreed) return;

    final username = _username.text.trim();
    final rawPhone = _normalizePhone(_phone.text.trim());
    final pin = _pin.text.trim();
    final phone = _formatPhone(rawPhone);

    setState(() => _isSendingOtp = true);

    try {
      // ── Check username uniqueness ────────────────────────────────────────
      final usernameExists = await UserService().usernameExists(username);
      if (usernameExists) {
        if (!mounted) return;
        setState(() {
          _isSendingOtp = false;
          _usernameServerError =
              "Username is already taken. Please choose another.";
        });
        _formKey.currentState!.validate();
        return;
      }

      // ── Check phone in SQLite ────────────────────────────────────────────
      final phoneExistsLocal = await UserService().phoneExists(phone);
      if (phoneExistsLocal) {
        if (!mounted) return;
        setState(() {
          _isSendingOtp = false;
          _phoneServerError =
              "This number is already registered. Please login instead.";
        });
        _formKey.currentState!.validate();
        return;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isSendingOtp = false);
          _snack("Error: ${e.message ?? 'Failed to send OTP'}");
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
                isSignUp: true,
                username: username,
                pin: pin,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSendingOtp = false);
      _snack("Error: $e");
    }
  }

  Future<void> _showTerms() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TermsDialog(),
    );

    if (accepted == true && mounted) {
      // Auto-check the checkbox once the terms have been read.
      setState(() {
        _hasViewedTerms = true;
        _agreed = true;
        _termsError = null;
      });
    }
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
            colors: [_primaryBlue, _heroBlue],
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
                  onTap: _isSendingOtp ? null : () => Navigator.pop(context),
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
            const Positioned(
              left: 26,
              right: 26,
              bottom: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create account',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Join PARE and stay ahead of scam calls',
                    style: TextStyle(
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
      focusedBorder: border(_accentBlue, 1.4),
      errorBorder: border(_dangerColor, 1),
      focusedErrorBorder: border(_dangerColor, 1.4),
      errorStyle: const TextStyle(fontSize: 12, color: _dangerColor),
      errorMaxLines: 2,
    );
  }

  Widget _usernameField() {
    return TextFormField(
      controller: _username,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.next,
      maxLength: 30,
      style: const TextStyle(
        color: _inkColor,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: _pillDecoration(
        hint: 'Create your username',
        prefix: const AuthFieldIcon(AuthIcons.person),
      ),
      onChanged: (_) {
        if (_usernameServerError != null) _usernameServerError = null;
      },
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Username is required';
        return _usernameServerError;
      },
    );
  }

  Widget _phoneField() {
    return TextFormField(
      controller: _phone,
      keyboardType: TextInputType.number,
      maxLength: 11,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: _inkColor,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: _pillDecoration(
        hint: '9XX XXX XXXX',
        prefix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AuthFieldIcon(AuthIcons.phone),
            const SizedBox(width: 8),
            const Text(
              '+63',
              style: TextStyle(
                color: _inkColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 20, color: const Color(0xFFE4E9F0)),
          ],
        ),
      ),
      onChanged: (_) {
        if (_phoneServerError != null) _phoneServerError = null;
      },
      validator: (v) {
        if (v == null || v.isEmpty) return 'Phone number is required';

        final n = _normalizePhone(v);

        if (n.length != 11) return 'Please enter your 10-digit number';
        if (!n.startsWith('09')) return 'Must start with 9';

        return _phoneServerError;
      },
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      obscureText: obscure,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: _inkColor,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 2,
      ),
      decoration: _pillDecoration(
        hint: hint,
        prefix: const AuthFieldIcon(AuthIcons.pin),
        suffix: AuthPinVisibilityButton(obscured: obscure, onPressed: onToggle),
      ),
      validator: validator,
    );
  }

  Widget _termsRow() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _agreed,
                activeColor: _primaryBlue,
                side: BorderSide(
                  color: _hasViewedTerms ? _primaryBlue : Colors.grey.shade400,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                onChanged: _hasViewedTerms
                    ? (v) {
                        setState(() {
                          _agreed = v ?? false;
                          if (_agreed) _termsError = null;
                        });
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: GestureDetector(
                onTap: _showTerms,
                child: const Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _inkColor,
                    ),
                    children: [
                      TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms and Conditions',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _primaryBlue,
                          decoration: TextDecoration.underline,
                          decorationColor: _primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
        if (_termsError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _termsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _dangerColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _createButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isSendingOtp ? null : _createAccount,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBlue,
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
            : const Text(
                'Create account',
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

    final heroHeight = media.padding.top + 220;
    final sheetTop = heroHeight - 40;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _sheetColor,
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
                      color: _sheetColor,
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
                          const Text(
                            'Sign up',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _primaryBlue,
                            ),
                          ),

                          const SizedBox(height: 22),

                          _usernameField(),
                          const SizedBox(height: 14),

                          _phoneField(),
                          const SizedBox(height: 14),

                          _pinField(
                            controller: _pin,
                            hint: '6-digit MPIN',
                            obscure: _obscurePin,
                            onToggle: () =>
                                setState(() => _obscurePin = !_obscurePin),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'MPIN is required';
                              }
                              if (v.length != 6) {
                                return 'MPIN must be exactly 6 digits';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          _pinField(
                            controller: _confirmPin,
                            hint: 'Confirm MPIN',
                            obscure: _obscureConfirmPin,
                            onToggle: () => setState(
                              () => _obscureConfirmPin = !_obscureConfirmPin,
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Please confirm your MPIN';
                              }
                              if (v != _pin.text) return 'MPINs do not match';
                              return null;
                            },
                          ),

                          const SizedBox(height: 18),

                          SizedBox(width: double.infinity, child: _termsRow()),

                          const SizedBox(height: 18),

                          _createButton(),

                          const SizedBox(height: 22),

                          Center(
                            child: GestureDetector(
                              onTap: _isSendingOtp
                                  ? null
                                  : () {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const LoginScreen(),
                                        ),
                                      );
                                    },
                              child: const Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _mutedColor,
                                  ),
                                  children: [
                                    TextSpan(text: 'Already have an account? '),
                                    TextSpan(
                                      text: 'Login',
                                      style: TextStyle(
                                        color: _primaryBlue,
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
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Terms dialog ────────────────────────────────────────────────────────────

class _TermsDialog extends StatefulWidget {
  const _TermsDialog();

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  final _scrollController = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkBottom);

    // If the text is short enough to fit without scrolling, unlock right away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBottom());
  }

  void _checkBottom() {
    if (_reachedBottom || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 10) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Terms and Conditions',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _primaryBlue,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFE4E9F0)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(right: 10),
                  child: const Text(
                    _termsContent,
                    style: TextStyle(
                      color: _mutedColor,
                      fontSize: 13.5,
                      height: 1.65,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _reachedBottom ? 0 : 1,
              child: const Text(
                'Scroll down to read all terms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9AA4B2),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _reachedBottom
                    ? () => Navigator.pop(context, true)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _primaryBlue.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
                  elevation: _reachedBottom ? 4 : 0,
                  shadowColor: const Color.fromRGBO(9, 44, 86, 0.35),
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'I have read this',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const String _termsContent = '''
Welcome to PARE (Protecting All Random Exchanges). By creating an account, you agree to the following terms:

1. PURPOSE OF THE APP
PARE is a scam and deepfake voice call detection assistance tool. It provides real-time alerts and detection support to help users identify potentially fraudulent calls.

2. USER RESPONSIBILITIES
You agree to use PARE only for lawful purposes. You must not use the app to harass, deceive, or harm other individuals. You are responsible for maintaining the confidentiality of your account credentials.

3. DETECTION LIMITATIONS
PARE provides detection support and alerts, but it does not guarantee 100% accuracy. Users must still exercise personal judgment and make safe, informed decisions when receiving calls.

4. DATA & PRIVACY
We collect minimal personal data necessary to operate the app, including your phone number and username. Your data will not be sold to third parties. For more details, refer to our Privacy Policy.

5. ACCOUNT SECURITY
You are responsible for keeping your 6-digit MPIN confidential. PARE will never ask for your MPIN through a call or message. Report any suspicious activity immediately.

6. MODIFICATIONS TO TERMS
PARE reserves the right to update these Terms and Conditions at any time. Continued use of the app after changes constitutes acceptance of the new terms.

7. DISCLAIMER
PARE is provided "as is" without warranties of any kind. We are not liable for any damages arising from the use or inability to use the app.

By tapping "Create account", you acknowledge that you have read, understood, and agree to be bound by these Terms and Conditions.
''';
