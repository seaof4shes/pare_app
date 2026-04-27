import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  String? _usernameError;
  String? _phoneError;
  String? _termsError;

  bool _agreed = false;
  bool _isSendingOtp = false;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF253F5D);
  static const Color whiteText = Color(0xFFF0F5F4);

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
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
      _termsError = null;
    });

    final username = _username.text.trim();
    final rawPhone = _phone.text.trim();

    bool hasError = false;

    if (username.isEmpty) {
      _usernameError = "Username is required";
      hasError = true;
    }

    if (rawPhone.isEmpty) {
      _phoneError = "Phone number is required";
      hasError = true;
    } else if (rawPhone.length != 11) {
      _phoneError = "Please enter 11-digit phone number";
      hasError = true;
    } else if (!rawPhone.startsWith('09')) {
      _phoneError = "Phone number must start with 09";
      hasError = true;
    }

    if (!_agreed) {
      _termsError = "Please agree to the Terms & Conditions";
      hasError = true;
    }

    if (hasError) {
      setState(() {});
      return;
    }

    final phone = _formatPhone(rawPhone);

    setState(() => _isSendingOtp = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(phone)
          .get();

      if (userDoc.exists) {
        if (!mounted) return;
        setState(() => _isSendingOtp = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account already exists. Please login instead."),
          ),
        );
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    int? maxLength,
  }) {
    return SizedBox(
      height: 68,
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        maxLength: maxLength,
        inputFormatters: keyboard == TextInputType.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        cursorColor: Colors.white,
        style: const TextStyle(color: whiteText, fontSize: 16),
        decoration: InputDecoration(
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.never,
          labelText: label,
          counterText: "",
          filled: true,
          fillColor: cardBlue,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 16),
          suffixIcon: Icon(icon, color: whiteText),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.white),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.white),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.white, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  Widget _errorText(String? error) {
    if (error == null) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 5),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          error,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showTerms() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Terms & Conditions"),
        content: const SingleChildScrollView(
          child: Text(
            "By creating an account, you agree to use P.A.R.E. as a scam and deepfake voice call detection assistance tool. The app provides alerts and detection support, but users should still make safe decisions.",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF0F4F8),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      const Text(
                        "P.A.R.E",
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          color: primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Protecting All Random Exchange",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 25),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cardBlue,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "Sign Up",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: whiteText,
                              ),
                            ),
                            const SizedBox(height: 18),
                            _field(
                              controller: _username,
                              label: "Username",
                              icon: Icons.person_outline,
                            ),
                            _errorText(_usernameError),
                            const SizedBox(height: 12),
                            _field(
                              controller: _phone,
                              label: "Phone Number",
                              icon: Icons.phone,
                              keyboard: TextInputType.number,
                              maxLength: 11,
                            ),
                            _errorText(_phoneError),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: _agreed,
                            activeColor: primaryBlue,
                            onChanged: (v) {
                              setState(() {
                                _agreed = v ?? false;
                                if (_agreed) _termsError = null;
                              });
                            },
                          ),
                          const Text("I agree to "),
                          GestureDetector(
                            onTap: _showTerms,
                            child: const Text(
                              "Terms & Conditions",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryBlue,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                      _errorText(_termsError),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 260,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSendingOtp ? null : _createAccount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            disabledBackgroundColor: Colors.grey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isSendingOtp
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Create Account",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: whiteText,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 25),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Already have an account? "),
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
                        fontWeight: FontWeight.bold,
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
