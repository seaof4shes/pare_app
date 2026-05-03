import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pare_app/core/database/user_service.dart';

import 'login_screen.dart';
import 'otp_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _confirmPin = TextEditingController();

  String? _usernameError;
  String? _phoneError;
  String? _pinError;
  String? _confirmPinError;
  String? _termsError;

  bool _agreed = false;
  bool _hasViewedTerms = false;
  bool _isSendingOtp = false;
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF1E3A5F);
  static const Color whiteText = Color(0xFFF0F5F4);

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
    _pin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  String _formatPhone(String rawPhone) {
    return rawPhone.startsWith('0')
        ? '+63${rawPhone.substring(1)}'
        : '+63$rawPhone';
  }

  Future<void> _createAccount() async {
    setState(() {
      _usernameError = null;
      _phoneError = null;
      _pinError = null;
      _confirmPinError = null;
      _termsError = null;
    });

    final username = _username.text.trim();
    final rawPhone = _phone.text.trim();
    final pin = _pin.text.trim();
    final confirmPin = _confirmPin.text.trim();

    bool hasError = false;

    if (username.isEmpty) {
      _usernameError = "Username is required";
      hasError = true;
    }

    if (rawPhone.isEmpty) {
      _phoneError = "Phone number is required";
      hasError = true;
    } else if (rawPhone.length != 11) {
      _phoneError = "Please enter an 11-digit phone number";
      hasError = true;
    } else if (!rawPhone.startsWith('09')) {
      _phoneError = "Phone number must start with 09";
      hasError = true;
    }

    if (pin.isEmpty) {
      _pinError = "PIN is required";
      hasError = true;
    } else if (pin.length != 6) {
      _pinError = "PIN must be exactly 6 digits";
      hasError = true;
    }

    if (confirmPin.isEmpty) {
      _confirmPinError = "Please confirm your PIN";
      hasError = true;
    } else if (pin != confirmPin) {
      _confirmPinError = "PINs do not match";
      hasError = true;
    }

    if (!_agreed) {
      _termsError = !_hasViewedTerms
          ? "Please read the Terms & Conditions first"
          : "You must agree to the Terms & Conditions";
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    final phone = _formatPhone(rawPhone);
    setState(() => _isSendingOtp = true);

    try {
      // ── Check username uniqueness ──────────────────────────────────────────
      final usernameExists = await UserService().usernameExists(username);
      if (usernameExists) {
        if (!mounted) return;
        setState(() {
          _isSendingOtp = false;
          _usernameError = "Username is already taken. Please choose another.";
        });
        return;
      }

      // ── Check phone in SQLite ──────────────────────────────────────────────
      final phoneExistsLocal = await UserService().phoneExists(phone);
      if (phoneExistsLocal) {
        if (!mounted) return;
        setState(() {
          _isSendingOtp = false;
          _phoneError =
              "This number is already registered. Please login instead.";
        });
        return;
      }

      final phoneExistsFirebase = await UserService().phoneExistsInFirebase(
        phone,
      );
      if (phoneExistsFirebase) {
        if (!mounted) return;
        setState(() {
          _isSendingOtp = false;
          _phoneError =
              "This number is already registered. Please login instead.";
        });
        return;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isSendingOtp = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error: ${e.message ?? 'Failed to send OTP'}"),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ── Field builder ──────────────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData suffixIcon,
    TextInputType keyboard = TextInputType.text,
    int? maxLength,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: keyboard,
          maxLength: maxLength,
          obscureText: obscure,
          inputFormatters: keyboard == TextInputType.number
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          cursorColor: Colors.white,
          style: const TextStyle(color: whiteText, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
            counterText: "",
            filled: true,
            fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
            suffixIcon: onToggleObscure != null
                ? GestureDetector(
                    onTap: onToggleObscure,
                    child: Icon(
                      obscure ? Icons.lock_outline : Icons.lock_open_outlined,
                      color: Colors.white60,
                      size: 20,
                    ),
                  )
                : Icon(suffixIcon, color: Colors.white60, size: 20),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 17,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color.fromRGBO(255, 255, 255, 0.25),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white54),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 5),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  // ── Terms overlay ──────────────────────────────────────────────────────────
  void _showTerms() {
    // Track whether the user has scrolled to the bottom inside the dialog
    bool reachedBottom = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final scrollController = ScrollController();

            scrollController.addListener(() {
              if (!reachedBottom &&
                  scrollController.position.pixels >=
                      scrollController.position.maxScrollExtent - 10) {
                setDialogState(() => reachedBottom = true);
              }
            });

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: const Color(0xFF1E3A5F),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title (centered) ───────────────────────────────────
                    Row(
                      children: const [
                        Icon(
                          Icons.gavel_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              "Terms & Conditions",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: whiteText,
                              ),
                            ),
                          ),
                        ),
                        // Invisible spacer to balance the icon
                        SizedBox(width: 22),
                      ],
                    ),

                    const SizedBox(height: 4),
                    const Divider(color: Color.fromRGBO(255, 255, 255, 0.2)),
                    const SizedBox(height: 8),

                    // ── Scrollable content ─────────────────────────────────
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: const Text(
                          _termsContent,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Scroll hint (shown until bottom reached) ───────────
                    if (!reachedBottom)
                      const Center(
                        child: Text(
                          "Scroll down to read all terms",
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white38,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // ── Button (disabled until scrolled to bottom) ─────────
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: reachedBottom
                            ? () {
                                // Auto-check the checkbox when confirmed
                                setState(() {
                                  _hasViewedTerms = true;
                                  _agreed = true;
                                  _termsError = null;
                                });
                                Navigator.pop(dialogContext);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryBlue,
                          disabledBackgroundColor: primaryBlue.withValues(
                            alpha: 0.35,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "I have read this",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: reachedBottom
                                ? whiteText
                                : whiteText.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static const String _termsContent = '''
Welcome to P.A.R.E. (Protecting All Random Exchanges). By creating an account, you agree to the following terms:

1. PURPOSE OF THE APP
P.A.R.E. is a scam and deepfake voice call detection assistance tool. It provides real-time alerts and detection support to help users identify potentially fraudulent calls.

2. USER RESPONSIBILITIES
You agree to use P.A.R.E. only for lawful purposes. You must not use the app to harass, deceive, or harm other individuals. You are responsible for maintaining the confidentiality of your account credentials.

3. DETECTION LIMITATIONS
P.A.R.E. provides detection support and alerts, but it does not guarantee 100% accuracy. Users must still exercise personal judgment and make safe, informed decisions when receiving calls.

4. DATA & PRIVACY
We collect minimal personal data necessary to operate the app, including your phone number and username. Your data will not be sold to third parties. For more details, refer to our Privacy Policy.

5. ACCOUNT SECURITY
You are responsible for keeping your 6-digit PIN confidential. P.A.R.E. will never ask for your PIN through a call or message. Report any suspicious activity immediately.

6. MODIFICATIONS TO TERMS
P.A.R.E. reserves the right to update these Terms & Conditions at any time. Continued use of the app after changes constitutes acceptance of the new terms.

7. DISCLAIMER
P.A.R.E. is provided "as is" without warranties of any kind. We are not liable for any damages arising from the use or inability to use the app.

By tapping "Create Account", you acknowledge that you have read, understood, and agree to be bound by these Terms & Conditions.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF2F5F8),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            "P.A.R.E",
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: primaryBlue,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: Color.fromRGBO(9, 44, 86, 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.security,
                              color: primaryBlue,
                              size: 26,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: cardBlue,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(9, 44, 86, 0.25),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Center(
                              child: Text(
                                "Sign up",
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: whiteText,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),

                            const SizedBox(height: 22),

                            _buildField(
                              controller: _username,
                              hint: "Create your username",
                              suffixIcon: Icons.person_outline,
                              errorText: _usernameError,
                            ),

                            const SizedBox(height: 14),

                            _buildField(
                              controller: _phone,
                              hint: "Enter your phone number",
                              suffixIcon: Icons.phone_outlined,
                              keyboard: TextInputType.number,
                              maxLength: 11,
                              errorText: _phoneError,
                            ),

                            const SizedBox(height: 14),

                            _buildField(
                              controller: _pin,
                              hint: "Create your 6-digit pin",
                              suffixIcon: Icons.lock_outline,
                              keyboard: TextInputType.number,
                              maxLength: 6,
                              obscure: _obscurePin,
                              onToggleObscure: () =>
                                  setState(() => _obscurePin = !_obscurePin),
                              errorText: _pinError,
                            ),

                            const SizedBox(height: 14),

                            _buildField(
                              controller: _confirmPin,
                              hint: "Confirm your 6-digit pin",
                              suffixIcon: Icons.lock_outline,
                              keyboard: TextInputType.number,
                              maxLength: 6,
                              obscure: _obscureConfirmPin,
                              onToggleObscure: () => setState(
                                () => _obscureConfirmPin = !_obscureConfirmPin,
                              ),
                              errorText: _confirmPinError,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Terms row
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _agreed,
                                  activeColor: primaryBlue,
                                  side: BorderSide(
                                    color: _hasViewedTerms
                                        ? primaryBlue
                                        : Colors.grey.shade400,
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

                              const Text(
                                "I agree to the ",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),

                              GestureDetector(
                                onTap: _showTerms,
                                child: const Text(
                                  "Terms and Condition.",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: primaryBlue,
                                    decoration: TextDecoration.underline,
                                    decorationColor: primaryBlue,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          if (_termsError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                _termsError!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Create Account button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSendingOtp ? null : _createAccount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            disabledBackgroundColor: Colors.grey.shade400,
                            elevation: 4,
                            shadowColor: const Color.fromRGBO(9, 44, 86, 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isSendingOtp
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text(
                                  "Create Account",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: whiteText,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Login footer
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Already have an account? ",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: const Text(
                      "Login",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: primaryBlue,
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
