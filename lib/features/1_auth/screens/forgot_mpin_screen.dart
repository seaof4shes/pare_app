import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:pare_app/core/database/user_service.dart';
import 'package:pare_app/core/utils/hash_helper.dart';
import 'login_screen.dart';

class ForgotMpinScreen extends StatefulWidget {
  const ForgotMpinScreen({super.key});

  @override
  State<ForgotMpinScreen> createState() => _ForgotMpinScreenState();
}

class _ForgotMpinScreenState extends State<ForgotMpinScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newMpinController = TextEditingController();
  final _confirmMpinController = TextEditingController();

  String? _verificationId;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _loading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF1E3A5F);
  static const Color whiteText = Color(0xFFF0F5F4);

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newMpinController.dispose();
    _confirmMpinController.dispose();
    super.dispose();
  }

  String _formatPhone(String rawPhone) {
    return rawPhone.startsWith('0')
        ? '+63${rawPhone.substring(1)}'
        : '+63$rawPhone';
  }

  Future<void> _sendOtp() async {
    final rawPhone = _phoneController.text.trim();

    if (rawPhone.length != 11 || !rawPhone.startsWith('09')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid 11-digit phone number")),
      );
      return;
    }

    final phone = _formatPhone(rawPhone);

    setState(() => _loading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (_) {},
      verificationFailed: (e) {
        if (!mounted) return;

        setState(() => _loading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Failed to send OTP")),
        );
      },
      codeSent: (verificationId, _) {
        if (!mounted) return;

        setState(() {
          _verificationId = verificationId;
          _otpSent = true;
          _loading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("OTP sent")));
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationId = verificationId;
      },
    );
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter 6-digit OTP")));
      return;
    }

    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please request an OTP first")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;

      setState(() {
        _otpVerified = true;
        _loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("OTP verified")));
    } catch (_) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
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
    final newHash = HashHelper.hashMpin(newMpin);

    return currentHash == newHash;
  }

  Future<void> _resetMpin() async {
    final phone = _formatPhone(_phoneController.text.trim());
    final newMpin = _newMpinController.text.trim();
    final confirmMpin = _confirmMpinController.text.trim();

    if (newMpin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("MPIN must be exactly 6 digits")),
      );
      return;
    }

    if (newMpin != confirmMpin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("MPINs do not match")));
      return;
    }

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

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "New MPIN must be different from your current MPIN",
              ),
            ),
          );
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("MPIN reset successfully")));

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData suffixIcon,
    Widget? suffixWidget,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54, fontSize: 15),
      filled: true,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.08),
      suffixIcon:
          suffixWidget ?? Icon(suffixIcon, color: Colors.white60, size: 20),
      counterText: "",
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
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLength = 11,
    bool obscure = false,
    Widget? suffixWidget,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: maxLength,
      obscureText: obscure,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      cursorColor: Colors.white,
      style: const TextStyle(color: whiteText, fontSize: 15),
      decoration: _fieldDecoration(
        hint: hint,
        suffixIcon: icon,
        suffixWidget: suffixWidget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = !_otpSent
        ? "Forgot MPIN"
        : !_otpVerified
        ? "Verify OTP"
        : "Reset MPIN";

    final subtitle = !_otpSent
        ? "Enter your phone number to receive an OTP."
        : !_otpVerified
        ? "Enter the 6-digit code sent to your phone."
        : "Create a new 6-digit MPIN different from your current one.";

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
                        child: Column(
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: whiteText,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (!_otpVerified) ...[
                              _inputField(
                                controller: _phoneController,
                                hint: "Phone number",
                                icon: Icons.phone_outlined,
                                maxLength: 11,
                              ),
                              if (_otpSent) ...[
                                const SizedBox(height: 14),
                                _inputField(
                                  controller: _otpController,
                                  hint: "Enter OTP",
                                  icon: Icons.sms_outlined,
                                  maxLength: 6,
                                ),
                              ],
                            ],
                            if (_otpVerified) ...[
                              _inputField(
                                controller: _newMpinController,
                                hint: "New 6-digit MPIN",
                                icon: Icons.lock_outline,
                                maxLength: 6,
                                obscure: _obscureNew,
                                suffixWidget: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _obscureNew = !_obscureNew;
                                    });
                                  },
                                  child: Icon(
                                    _obscureNew
                                        ? Icons.lock_outline
                                        : Icons.lock_open_outlined,
                                    color: Colors.white60,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _inputField(
                                controller: _confirmMpinController,
                                hint: "Confirm new MPIN",
                                icon: Icons.lock_outline,
                                maxLength: 6,
                                obscure: _obscureConfirm,
                                suffixWidget: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _obscureConfirm = !_obscureConfirm;
                                    });
                                  },
                                  child: Icon(
                                    _obscureConfirm
                                        ? Icons.lock_outline
                                        : Icons.lock_open_outlined,
                                    color: Colors.white60,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _loading
                              ? null
                              : !_otpSent
                              ? _sendOtp
                              : !_otpVerified
                              ? _verifyOtp
                              : _resetMpin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            disabledBackgroundColor: Colors.grey.shade400,
                            elevation: 4,
                            shadowColor: const Color.fromRGBO(9, 44, 86, 0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  !_otpSent
                                      ? "Send OTP"
                                      : !_otpVerified
                                      ? "Verify OTP"
                                      : "Reset MPIN",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: whiteText,
                                    letterSpacing: 0.5,
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
              padding: const EdgeInsets.only(bottom: 28),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text(
                  "Back to Login",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: primaryBlue,
                    decoration: TextDecoration.underline,
                    decorationColor: primaryBlue,
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
