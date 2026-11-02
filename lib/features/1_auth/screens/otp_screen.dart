import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pare_app/core/security/private_preferences.dart';

import 'package:pare_app/core/database/user_service.dart';
import 'package:pare_app/features/main_nav_screen.dart';

import 'signup_screen.dart';

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

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color cardBlue = Color(0xFF253F5D);
  static const Color whiteText = Color(0xFFF0F5F4);

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
      throw Exception('Unable to restore the P.A.R.E. account from Firebase.');
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

      // NEW:
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

  Widget _otpBox(int i) {
    return SizedBox(
      width: 42,
      height: 52,
      child: TextField(
        controller: _controllers[i],
        focusNode: _focusNodes[i],
        textAlign: TextAlign.center,
        maxLength: 1,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
          color: whiteText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: const Color(0xFF1C3550),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && i < 5) {
            FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
          }

          if (value.isEmpty && i > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[i - 1]);
          }
        },
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "P.A.R.E",
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: primaryBlue,
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        "Protecting All Random Exchange",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),

                      const SizedBox(height: 30),

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
                              "Account Verification",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: whiteText,
                              ),
                            ),

                            const SizedBox(height: 12),

                            Text(
                              "Code sent to $_maskedPhone",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),

                            const SizedBox(height: 25),

                            FittedBox(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  6,
                                  (index) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: _otpBox(index),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 18),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Didn’t receive? ",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap:
                                      _canResend &&
                                          !_isResending &&
                                          !_isVerifying
                                      ? _resendOtp
                                      : null,
                                  child: Text(
                                    _isResending
                                        ? 'Sending…'
                                        : _canResend
                                        ? "Resend OTP"
                                        : "${_secondsLeft}s",
                                    style: TextStyle(
                                      color: _canResend
                                          ? const Color(0xFF90B4D8)
                                          : Colors.white54,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: 300,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _isVerifying || _isResending
                              ? null
                              : _verifyOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            disabledBackgroundColor: Colors.grey,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isVerifying
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "Verify OTP",
                                  style: TextStyle(
                                    fontSize: 20,
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
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
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
