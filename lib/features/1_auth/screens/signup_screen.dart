import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';

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

  bool _agreed = false;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF253F5D);
  static const Color whiteText = Color(0xFFF0F5F4);

  @override
  void initState() {
    super.initState();

    _username.addListener(() {
      if (_username.text.trim().isNotEmpty && _usernameError != null) {
        setState(() => _usernameError = null);
      }
    });

    _phone.addListener(() {
      final value = _phone.text.trim();

      setState(() {
        if (value.isEmpty) {
          _phoneError = null;
        } else if (value.length != 11) {
          _phoneError = "Please enter 11-digit phone number";
        } else {
          _phoneError = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _createAccount() {
    setState(() {
      _usernameError = null;
      _phoneError = null;
    });

    final username = _username.text.trim();
    final phone = _phone.text.trim();

    bool hasError = false;

    if (username.isEmpty) {
      _usernameError = "Username is required";
      hasError = true;
    }

    if (phone.isEmpty) {
      _phoneError = "Phone number is required";
      hasError = true;
    } else if (phone.length != 11) {
      _phoneError = "Please enter 11-digit phone number";
      hasError = true;
    }

    if (!_agreed) hasError = true;

    if (hasError) {
      setState(() {});
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
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

        style: const TextStyle(
          color: whiteText,
          fontSize: 16,
          decoration: TextDecoration.none,
        ),

        decoration: InputDecoration(
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.never,

          labelText: label,
          counterText: "",

          filled: true,
          fillColor: cardBlue,

          labelStyle: const TextStyle(color: Colors.white70, fontSize: 16),

          suffixIcon: Icon(icon, color: whiteText),

          // ✅ FINAL FIX: KEEP BORDER + REMOVE UNDERLINE ISSUE
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
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red),
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

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, top: 5),
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
                            onChanged: (v) =>
                                setState(() => _agreed = v ?? false),
                          ),
                          const Text("I agree to "),
                          const Text(
                            "Terms & Conditions",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: primaryBlue,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: 260,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _createAccount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
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
