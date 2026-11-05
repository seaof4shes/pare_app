import 'package:flutter/material.dart';

/// Shared functional icons for authentication; no decorative app logos.
abstract final class AuthIcons {
  static const phone = Icons.phone_iphone_outlined;
  static const person = Icons.person_outline;
  static const pin = Icons.lock_outline;
  static const code = Icons.sms_outlined;
  static const size = 20.0;

  static Color color(bool onDark) =>
      onDark ? Colors.white70 : const Color(0xFF6B7686);
}

class AuthFieldIcon extends StatelessWidget {
  const AuthFieldIcon(this.icon, {super.key, this.onDark = false});

  final IconData icon;
  final bool onDark;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(icon, size: AuthIcons.size, color: AuthIcons.color(onDark)),
  );
}

class AuthPinVisibilityButton extends StatelessWidget {
  const AuthPinVisibilityButton({
    super.key,
    required this.obscured,
    required this.onPressed,
    this.onDark = false,
  });

  final bool obscured;
  final VoidCallback onPressed;
  final bool onDark;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: obscured ? 'Show MPIN' : 'Hide MPIN',
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    onPressed: onPressed,
    icon: Icon(
      // Hidden MPIN = closed eye; visible MPIN = open eye.
      obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: AuthIcons.size,
      color: AuthIcons.color(onDark),
    ),
  );
}
