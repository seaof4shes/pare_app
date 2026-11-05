import 'dart:async';

import '../widgets/auth_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pare_app/core/database/user_service.dart';
import 'package:pare_app/core/utils/hash_helper.dart';
import 'package:pare_app/core/utils/philippine_phone_formatter.dart';

import 'login_screen.dart';
import 'rings_painter.dart';

class ForgotMpinScreen extends StatefulWidget {
  const ForgotMpinScreen({super.key});

  @override
  State<ForgotMpinScreen> createState() => _ForgotMpinScreenState();
}

class _ForgotMpinScreenState extends State<ForgotMpinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _newMpinController = TextEditingController();
  final _confirmMpinController = TextEditingController();

  String? _verificationId;
  String? _verifiedPhone;
  String? _requestedPhone;
  int? _resendToken;

  bool _otpSent = false;
  bool _otpVerified = false;
  bool _loading = false;
  bool _autoValidate = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  Timer? _resendTimer;
  int _resendSeconds = 0;

  // Design tokens (same as LoginScreen)
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color heroBlue = Color(0xFF14437F);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color sheetColor = Color(0xFFEEF2F7);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color dangerColor = Color(0xFFC0392B);
  static const Color trackColor = Color(0xFFD5DCE6);

  String get _otp => _otpControllers.map((c) => c.text).join();

  /// 0 = send OTP, 1 = verify OTP, 2 = reset MPIN
  int get _step => !_otpSent
      ? 0
      : !_otpVerified
      ? 1
      : 2;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _newMpinController.dispose();
    _confirmMpinController.dispose();
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Accepts "9XXXXXXXXX" or "09XXXXXXXXX" and returns "09XXXXXXXXX".
  String _formatPhone(String rawPhone) {
    return '+63$rawPhone';
  }

  /// "+639123456789" -> "+63 912 345 6789"
  String _prettyPhone(String? phone) {
    if (phone == null || !phone.startsWith('+63') || phone.length != 13) {
      return phone ?? '';
    }
    final d = phone.substring(3);
    return '+63 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) t.cancel();
    });
  }

  /// Arrow / system back: step 1 leaves the screen, later steps go back one.
  void _onBack() {
    if (_loading) return;

    if (_step == 0) {
      Navigator.pop(context);
      return;
    }

    // Steps 2 and 3 both return to the phone step and clear verification.
    _resendTimer?.cancel();
    setState(() {
      _otpSent = false;
      _otpVerified = false;
      _verificationId = null;
      _verifiedPhone = null;
      _requestedPhone = null;
      _resendToken = null;
      _resendSeconds = 0;
      _autoValidate = false;
      _clearOtpFields();
      _newMpinController.clear();
      _confirmMpinController.clear();
    });
  }

  // ─── Logic ─────────────────────────────────────────────────────────────────

  Future<void> _sendOtp({bool resend = false}) async {
    if (_loading) return;

    final String phone;

    if (resend) {
      phone = _requestedPhone ?? '';
      if (phone.isEmpty) return;
    } else {
      setState(() => _autoValidate = true);
      if (!_formKey.currentState!.validate()) return;
      final rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');

      if (!RegExp(r'^9\d{9}$').hasMatch(rawPhone)) {
        _formKey.currentState!.validate();
        return;
      }

      phone = _formatPhone(rawPhone);
    }

    setState(() {
      _requestedPhone = phone;
      _otpVerified = false;
      _verifiedPhone = null;
      _loading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: resend ? _resendToken : null,
        verificationCompleted: (_) {},
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _loading = false);
          _snack(e.message ?? "Failed to send OTP");
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;

          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _otpSent = true;
            _loading = false;
            _autoValidate = false;
            _clearOtpFields();
          });

          // The cooldown only starts once the user has tapped "Resend OTP".
          if (resend) {
            _startResendCooldown();
            _otpFocusNodes[0].requestFocus();
          }
          _snack(resend ? "OTP resent successfully" : "OTP sent");
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack("Failed to send OTP");
    }
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;

    if (_otp.length != 6) {
      _snack("Enter 6-digit OTP");
      return;
    }

    if (_verificationId == null) {
      _snack("Please request an OTP first");
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;

      final verifiedPhone = FirebaseAuth.instance.currentUser?.phoneNumber;
      final matches = verifiedPhone != null && verifiedPhone == _requestedPhone;

      setState(() {
        _verifiedPhone = verifiedPhone;
        _otpVerified = matches;
        _loading = false;
        _autoValidate = false;
      });

      if (matches) {
        _resendTimer?.cancel();
        _snack("OTP verified");
      } else {
        _snack("This code doesn't match that phone number");
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack("Invalid OTP");
    }
  }

  Future<bool> _isSameAsCurrentMpin({
    required String phone,
    required String newMpin,
  }) async {
    final localUser = await UserService().getUserByPhone(phone);

    if (localUser == null) {
      return false;
    }

    final currentHash = localUser['mpin_hash'];
    return HashHelper.verify(newMpin, currentHash?.toString() ?? '');
  }

  Future<void> _resetMpin() async {
    if (_loading) return;

    final phone = _requestedPhone ?? '';

    if (!_otpVerified || phone.isEmpty || _verifiedPhone != phone) {
      _snack('Verify this phone number before resetting the MPIN.');
      return;
    }

    setState(() => _autoValidate = true);
    if (!_formKey.currentState!.validate()) return;

    final newMpin = _newMpinController.text.trim();

    setState(() => _loading = true);

    try {
      final localExists = await UserService().phoneExists(phone);

      if (localExists) {
        final sameAsCurrent = await _isSameAsCurrentMpin(
          phone: phone,
          newMpin: newMpin,
        );

        if (sameAsCurrent) {
          if (!mounted) return;
          setState(() => _loading = false);
          _snack("New MPIN must be different from your current MPIN");
          return;
        }

        await UserService().updateMpinLocal(
          phoneNumber: phone,
          newMpin: newMpin,
        );
      }

      await UserService().updateMpinFirestore(
        phoneNumber: phone,
        newMpin: newMpin,
      );

      if (!mounted) return;

      setState(() => _loading = false);

      _snack("MPIN reset successfully");

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack("Error: $e");
    }
  }

  void _onPrimaryPressed() {
    switch (_step) {
      case 0:
        _sendOtp();
        break;
      case 1:
        _verifyOtp();
        break;
      default:
        _resetMpin();
    }
  }

  // ─── UI pieces ─────────────────────────────────────────────────────────────

  Widget _hero(double height, double topInset) {
    final titles = ['Forgot MPIN?', 'Verify OTP', 'Reset MPIN'];
    final subtitles = [
      "We'll text you a code to reset it",
      'Enter the 6-digit code sent to ${_prettyPhone(_requestedPhone)}',
      'Pick a new 6-digit MPIN, different from your current one',
    ];

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
                  onTap: _loading ? null : _onBack,
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
                  Text(
                    titles[_step],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitles[_step],
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

  Widget _stepBar() {
    return Row(
      children: List.generate(3, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 4,
              decoration: BoxDecoration(
                color: i <= _step ? primaryBlue : trackColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
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
      inputFormatters: [PhilippinePhoneFormatter()],
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
            const AuthFieldIcon(AuthIcons.phone),
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
        final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');

        if (digits.isEmpty) {
          return 'Phone number is required';
        }

        if (!RegExp(r'^9\d{9}$').hasMatch(digits)) {
          return 'Enter 10 digits starting with 9 (e.g. 9123456789)';
        }

        return null;
      },
    );
  }

  /// Handles typing, deleting and pasting in box [i].
  ///
  /// More than one digit arriving at once (a paste, or typing over a filled
  /// box) is spread across this box and the ones after it.
  void _onOtpBoxChanged(int i, String value) {
    if (value.isEmpty) {
      if (i > 0) _otpFocusNodes[i - 1].requestFocus();
      return;
    }

    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.isEmpty) {
      _otpControllers[i].clear();
      return;
    }

    var last = i;

    for (var j = 0; j < digits.length && i + j < 6; j++) {
      last = i + j;
      _otpControllers[last].value = TextEditingValue(
        text: digits[j],
        selection: const TextSelection.collapsed(offset: 1),
      );
    }

    _otpFocusNodes[last < 5 ? last + 1 : 5].requestFocus();
  }

  Widget _otpBox(int i) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );

    return SizedBox(
      height: 54,
      child: TextField(
        controller: _otpControllers[i],
        focusNode: _otpFocusNodes[i],
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
          final c = _otpControllers[i];
          c.selection = TextSelection(
            baseOffset: 0,
            extentOffset: c.text.length,
          );
        },
        onChanged: (value) => _onOtpBoxChanged(i, value),
      ),
    );
  }

  Widget _otpBoxes() {
    return Row(
      children: List.generate(6, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
            child: _otpBox(i),
          ),
        );
      }),
    );
  }

  Widget _mpinField({
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
        color: inkColor,
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

  Widget _primaryButton() {
    final labels = ['Send OTP', 'Verify OTP', 'Reset MPIN'];

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : _onPrimaryPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade400,
          elevation: 4,
          shadowColor: const Color.fromRGBO(9, 44, 86, 0.35),
          shape: const StadiumBorder(),
        ),
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                labels[_step],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
      ),
    );
  }

  Widget _linkText({
    required String lead,
    required String action,
    required VoidCallback? onTap,
  }) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 13, color: mutedColor),
            children: [
              TextSpan(text: '$lead '),
              TextSpan(
                text: action,
                style: const TextStyle(
                  color: primaryBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resendRow() {
    final canResend = _resendSeconds <= 0 && !_loading;

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
                onTap: canResend ? () => _sendOtp(resend: true) : null,
                child: Text(
                  _resendSeconds > 0 ? '${_resendSeconds}s' : 'Resend OTP',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: canResend ? accentBlue : const Color(0xFF9AA4B2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stepContent() {
    switch (_step) {
      case 0:
        return [
          _sheetTitle('Your phone'),
          const SizedBox(height: 22),
          _phoneField(),
          const SizedBox(height: 20),
          _primaryButton(),
          const SizedBox(height: 22),
          _linkText(
            lead: 'Remembered it?',
            action: 'Back to login',
            onTap: _loading ? null : () => Navigator.pop(context),
          ),
        ];
      case 1:
        return [
          _sheetTitle('Verification'),
          const SizedBox(height: 22),
          _otpBoxes(),
          const SizedBox(height: 18),
          _resendRow(),
          const SizedBox(height: 20),
          _primaryButton(),
          const SizedBox(height: 22),
          _linkText(
            lead: 'Wrong number?',
            action: 'Change it',
            onTap: _loading ? null : _onBack,
          ),
        ];
      default:
        return [
          _sheetTitle('New MPIN'),
          const SizedBox(height: 22),
          _mpinField(
            controller: _newMpinController,
            hint: 'New 6-digit MPIN',
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
            validator: (v) {
              if (v == null || v.isEmpty) return 'MPIN is required';
              if (!RegExp(r'^\d{6}$').hasMatch(v)) {
                return 'MPIN must be exactly 6 digits';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          _mpinField(
            controller: _confirmMpinController,
            hint: 'Confirm new MPIN',
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Confirm your new MPIN';
              if (v != _newMpinController.text) return 'MPINs do not match';
              return null;
            },
          ),
          const SizedBox(height: 20),
          _primaryButton(),
        ];
    }
  }

  Widget _sheetTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: primaryBlue,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    final heroHeight = media.padding.top + 260;
    final sheetTop = heroHeight - 40;

    return PopScope(
      canPop: _step == 0 && !_loading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                        26,
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
                            _stepBar(),
                            const SizedBox(height: 22),
                            ..._stepContent(),
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
      ),
    );
  }
}
