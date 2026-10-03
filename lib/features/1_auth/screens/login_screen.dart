import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pare_app/core/database/user_service.dart';
import 'package:pare_app/features/main_nav_screen.dart';

import 'signup_screen.dart';
import 'otp_screen.dart';
import 'package:pare_app/features/1_auth/screens/forgot_mpin_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF1E3A5F);
  static const Color whiteText = Color(0xFFF0F5F4);

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String _formatPhone(String rawPhone) {
    return rawPhone.startsWith('0')
        ? '+63${rawPhone.substring(1)}'
        : '+63$rawPhone';
  }

  Future<void> _onLogin() async {
    setState(() => _autoValidate = true);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final rawPhone = _phoneController.text.trim();
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
      final prefs = await SharedPreferences.getInstance();

      // ==========================================================
      // 1. CHECK LOCAL ACCOUNT
      // ==========================================================

      final localAccountExists = await userService.phoneExists(phone);

      // ==========================================================
      // 2. FRESH INSTALL / LOCAL ACCOUNT MISSING
      // ==========================================================
      //
      // IMPORTANT:
      // Do NOT query Firestore here.
      //
      // Firestore requires request.auth != null, but the user has
      // not completed Firebase Phone Authentication yet.
      //
      // Instead, Firebase OTP will authenticate the phone first.
      //
      // After successful OTP verification, OtpScreen will restore
      // the account from Firestore using the authenticated Firebase UID.
      //
      // ==========================================================

      if (!localAccountExists) {
        await prefs.setString('pending_login_phone', phone);
        await prefs.setBool('isLoggedIn', false);

        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phone,

          // --------------------------------------------------------
          // AUTOMATIC VERIFICATION
          // --------------------------------------------------------
          verificationCompleted: (PhoneAuthCredential credential) async {
            try {
              await FirebaseAuth.instance.signInWithCredential(credential);

              // Firebase authentication is now complete.
              //
              // Restore the local account from Firestore using the
              // authenticated Firebase UID.
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

          // --------------------------------------------------------
          // VERIFICATION FAILED
          // --------------------------------------------------------
          verificationFailed: (FirebaseAuthException e) {
            if (!mounted) return;

            setState(() => _isSendingOtp = false);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Unable to send OTP: ${e.message ?? e.code}"),
              ),
            );
          },

          // --------------------------------------------------------
          // OTP SENT
          // --------------------------------------------------------
          codeSent: (String verificationId, int? resendToken) {
            if (!mounted) return;

            setState(() => _isSendingOtp = false);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtpScreen(
                  phone: phone,
                  verificationId: verificationId,

                  // Login, not signup.
                  isSignUp: false,
                  isLogin: true,

                  // Needed so OtpScreen can establish the MPIN
                  // locally after Firebase authentication.
                  pin: pin,
                ),
              ),
            );
          },

          // --------------------------------------------------------
          // AUTO RETRIEVAL TIMEOUT
          // --------------------------------------------------------
          codeAutoRetrievalTimeout: (String verificationId) {
            // OtpScreen handles manual OTP entry.
          },
        );

        return;
      }

      // ==========================================================
      // 3. LOCAL ACCOUNT EXISTS
      // ==========================================================
      //
      // Existing-device login continues using the local MPIN.
      //
      // ==========================================================

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

      // ==========================================================
      // 4. CHECK WHETHER OTP IS REQUIRED
      // ==========================================================

      final requireOtp = prefs.getBool('requireOtp') ?? false;

      // ==========================================================
      // 5. NORMAL LOGIN
      // ==========================================================

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

      // ==========================================================
      // 6. EXISTING DEVICE LOGIN → REQUIRE OTP
      // ==========================================================

      await prefs.setString('pending_login_phone', phone);
      await prefs.setBool('isLoggedIn', false);

      // ==========================================================
      // 7. SEND FIREBASE OTP
      // ==========================================================

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,

        // --------------------------------------------------------
        // AUTOMATIC VERIFICATION
        // --------------------------------------------------------
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);

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

        // --------------------------------------------------------
        // VERIFICATION FAILED
        // --------------------------------------------------------
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;

          setState(() => _isSendingOtp = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Unable to send OTP: ${e.message ?? e.code}"),
            ),
          );
        },

        // --------------------------------------------------------
        // OTP SENT
        // --------------------------------------------------------
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

        // --------------------------------------------------------
        // AUTO RETRIEVAL TIMEOUT
        // --------------------------------------------------------
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

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData suffixIcon,
    Widget? suffixWidget,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Colors.white54,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
      suffixIcon:
          suffixWidget ?? Icon(suffixIcon, color: Colors.white60, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      errorStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Colors.redAccent,
      ),
    );
  }

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
                      // ==================================================
                      // LOGO
                      // ==================================================
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

                      const SizedBox(height: 6),

                      const Text(
                        "Protecting All Random Exchanges",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                          letterSpacing: 0.3,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ==================================================
                      // LOGIN CARD
                      // ==================================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 30,
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
                        child: Form(
                          key: _formKey,
                          autovalidateMode: _autoValidate
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Center(
                                child: Text(
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: whiteText,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // ==================================================
                              // PHONE NUMBER
                              // ==================================================
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.number,
                                maxLength: 11,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  color: whiteText,
                                  fontSize: 15,
                                ),
                                decoration: _fieldDecoration(
                                  hint: "Phone number",
                                  suffixIcon: Icons.person_outline,
                                ).copyWith(counterText: ""),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return "Phone number is required";
                                  }

                                  if (v.length != 11) {
                                    return "Please enter an 11-digit number";
                                  }

                                  if (!v.startsWith('09')) {
                                    return "Must start with 09";
                                  }

                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              // ==================================================
                              // MPIN
                              // ==================================================
                              TextFormField(
                                controller: _pinController,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                obscureText: _obscurePin,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  color: whiteText,
                                  fontSize: 15,
                                ),
                                decoration: _fieldDecoration(
                                  hint: "6-digit PIN",
                                  suffixIcon: Icons.lock_outline,
                                  suffixWidget: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _obscurePin = !_obscurePin;
                                      });
                                    },
                                    child: Icon(
                                      _obscurePin
                                          ? Icons.lock_outline
                                          : Icons.lock_open_outlined,
                                      color: Colors.white60,
                                      size: 20,
                                    ),
                                  ),
                                ).copyWith(counterText: ""),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return "PIN is required";
                                  }

                                  if (v.length != 6) {
                                    return "PIN must be exactly 6 digits";
                                  }

                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ==================================================
                      // LOGIN BUTTON
                      // ==================================================
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSendingOtp ? null : _onLogin,
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
                                  "Login",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: whiteText,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ==================================================
                      // FORGOT MPIN
                      // ==================================================
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotMpinScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryBlue,
                            decoration: TextDecoration.underline,
                            decorationColor: primaryBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ==================================================
            // SIGN-UP FOOTER
            // ==================================================
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text(
                      "Sign up",
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
