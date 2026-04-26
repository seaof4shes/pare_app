import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'signup_screen.dart';
import 'otp_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  bool _autoValidate = false;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF253F5D);
  static const Color whiteText = Color(0xFFF0F5F4);

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset:
          false, // 🔥 prevents movement when keyboard opens
      backgroundColor: const Color(0xFFF0F4F8),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "P.A.R.E",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          color: primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 10),

                      const Text(
                        "Protecting All Random Exchange",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),

                      const SizedBox(height: 35),

                      // ================= LOGIN CARD =================
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: cardBlue,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: _autoValidate
                              ? AutovalidateMode.onUserInteraction
                              : AutovalidateMode.disabled,
                          child: Column(
                            children: [
                              const Text(
                                "Login",
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: whiteText,
                                ),
                              ),

                              const SizedBox(height: 25),

                              // ================= PHONE FIELD =================
                              SizedBox(
                                height: 78, // stable height for elders
                                child: TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.number,
                                  maxLength: 11,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: const TextStyle(
                                    color: whiteText,
                                    fontSize: 18,
                                  ),

                                  decoration: InputDecoration(
                                    labelText: "Phone Number",
                                    labelStyle: const TextStyle(
                                      color: Colors.white70,
                                      fontSize:
                                          17, // slightly bigger floating label
                                    ),

                                    hintText: "Enter 11-digit number",
                                    hintStyle: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 16,
                                    ),

                                    counterText: "",

                                    filled: true,
                                    fillColor: cardBlue,

                                    // RIGHT ICON (kept as requested)
                                    suffixIcon: const Icon(
                                      Icons.phone,
                                      color: whiteText,
                                    ),

                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 22,
                                    ),

                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: const BorderSide(
                                        color: Colors.white,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: const BorderSide(
                                        color: Colors.white,
                                      ),
                                    ),
                                    errorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: const BorderSide(
                                        color: Colors.white,
                                      ),
                                    ),
                                    focusedErrorBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(18),
                                      borderSide: const BorderSide(
                                        color: Colors.white,
                                      ),
                                    ),

                                    // BIGGER ERROR TEXT FOR ELDERLY
                                    errorStyle: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.redAccent,
                                    ),
                                  ),

                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return "Phone number is required";
                                    }
                                    if (v.length != 11) {
                                      return "Please enter 11-digit phone number";
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 35),

                      // ================= SEND OTP BUTTON =================
                      SizedBox(
                        width: 300, // slightly shorter (your request)
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _onLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            "Send OTP",
                            style: TextStyle(
                              fontSize: 22,
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

            // ================= BOTTOM SIGN UP (FIXED POSITION) =================
            Padding(
              padding: const EdgeInsets.only(bottom: 25),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
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
                      "Sign-Up",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
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

  void _onLogin() async {
    setState(() => _autoValidate = true);

    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: "+63$phone", // 🇵🇭 format

      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto verification (rare)
        await FirebaseAuth.instance.signInWithCredential(credential);
      },

      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: ${e.message}")));
      },

      codeSent: (String verificationId, int? resendToken) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              phone: phone,
              verificationId: verificationId, // 🔥 REQUIRED
            ),
          ),
        );
      },

      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }
}
