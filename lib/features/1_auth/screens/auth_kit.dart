import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pare_app/features/1_auth/screens/rings_painter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens (same palette as the original login screen)
// ─────────────────────────────────────────────────────────────────────────────
class AuthColors {
  static const Color primary = Color(0xFF092C56);
  static const Color hero = Color(0xFF14437F);
  static const Color accent = Color(0xFF2A5298);
  static const Color sheet = Color(0xFFEEF2F7);
  static const Color ink = Color(0xFF10192B);
  static const Color muted = Color(0xFF6B7686);
  static const Color hint = Color(0xFF9AA4B2);
  static const Color border = Color(0xFFDDE3EC);
  static const Color danger = Color(0xFFC0392B);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Accepts "9XXXXXXXXX" or "09XXXXXXXXX" and returns "09XXXXXXXXX".
String normalizePhone(String v) {
  final t = v.trim();
  if (t.length == 10 && t.startsWith('9')) return '0$t';
  return t;
}

/// "09XXXXXXXXX" -> "+639XXXXXXXXX"
String formatPhone(String rawPhone) {
  return rawPhone.startsWith('0')
      ? '+63${rawPhone.substring(1)}'
      : '+63$rawPhone';
}

void showAuthSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AuthColors.ink,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Scaffold: blue hero on top + rounded sheet that holds the content
// ─────────────────────────────────────────────────────────────────────────────
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? sheetTitle;
  final String? sheetSubtitle;
  final VoidCallback? onBack;
  final Widget child;
  final Widget? footer;
  final double heroContentHeight;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.sheetTitle,
    this.sheetSubtitle,
    this.onBack,
    this.footer,
    this.heroContentHeight = 230,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final heroHeight = media.padding.top + heroContentHeight;
    final sheetTop = heroHeight - 36;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AuthColors.sheet,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: heroHeight,
                child: _Hero(
                  title: title,
                  subtitle: subtitle,
                  height: heroHeight,
                  topInset: media.padding.top,
                  onBack: onBack,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: sheetTop),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: media.size.height - sheetTop,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      30,
                      24,
                      24 + media.padding.bottom,
                    ),
                    decoration: const BoxDecoration(
                      color: AuthColors.sheet,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(36),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (sheetTitle != null)
                          Text(
                            sheetTitle!,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AuthColors.primary,
                            ),
                          ),
                        if (sheetSubtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            sheetSubtitle!,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: AuthColors.muted,
                            ),
                          ),
                        ],
                        if (sheetTitle != null || sheetSubtitle != null)
                          const SizedBox(height: 24),
                        child,
                        if (footer != null) ...[
                          const SizedBox(height: 24),
                          Center(child: footer!),
                        ],
                      ],
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

class _Hero extends StatelessWidget {
  final String title;
  final String subtitle;
  final double height;
  final double topInset;
  final VoidCallback? onBack;

  const _Hero({
    required this.title,
    required this.subtitle,
    required this.height,
    required this.topInset,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Container(
        height: height,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AuthColors.primary, AuthColors.hero],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              left: -80,
              top: -80,
              child: CustomPaint(size: Size(240, 240), painter: RingsPainter()),
            ),
            if (onBack != null)
              Positioned(
                top: topInset + 8,
                left: 16,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: Colors.white,
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
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
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

// ─────────────────────────────────────────────────────────────────────────────
// Text field. Set isSecret: true for MPIN fields and the eye toggle is handled
// INSIDE the field, so no screen has to manage its own obscure flag.
//   hidden  -> eye with a slash (tap to show)
//   visible -> open eye         (tap to hide)
// ─────────────────────────────────────────────────────────────────────────────
class AuthField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? prefixText;
  final bool isSecret;
  final bool digitsOnly;
  final TextInputType keyboardType;
  final int? maxLength;
  final String? errorText;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool autofocus;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.prefixText,
    this.isSecret = false,
    this.digitsOnly = false,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.errorText,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.readOnly = false,
    this.autofocus = false,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true;

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: BorderSide(color: color, width: width),
  );

  @override
  Widget build(BuildContext context) {
    final obscured = widget.isSecret && _hidden;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AuthColors.ink,
            ),
          ),
        ),
        TextFormField(
          controller: widget.controller,
          readOnly: widget.readOnly,
          autofocus: widget.autofocus,
          obscureText: obscured,
          obscuringCharacter: '●',
          enableSuggestions: !widget.isSecret,
          autocorrect: !widget.isSecret,
          keyboardType: widget.isSecret || widget.digitsOnly
              ? TextInputType.number
              : widget.keyboardType,
          maxLength: widget.maxLength,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          validator: widget.validator,
          inputFormatters: widget.isSecret || widget.digitsOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          cursorColor: AuthColors.accent,
          style: TextStyle(
            color: widget.readOnly ? AuthColors.muted : AuthColors.ink,
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
            letterSpacing: obscured ? 3 : 0.3,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: widget.hint,
            hintStyle: const TextStyle(
              color: AuthColors.hint,
              fontSize: 14.5,
              letterSpacing: 0,
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: widget.readOnly ? const Color(0xFFE6EBF2) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 17,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 18, right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 20, color: AuthColors.muted),
                  if (widget.prefixText != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      widget.prefixText!,
                      style: const TextStyle(
                        color: AuthColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 20, color: AuthColors.border),
                  ],
                ],
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: widget.isSecret
                ? IconButton(
                    tooltip: _hidden ? 'Show MPIN' : 'Hide MPIN',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(
                      _hidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 21,
                      color: _hidden ? AuthColors.muted : AuthColors.accent,
                    ),
                  )
                : null,
            errorText: widget.errorText,
            errorMaxLines: 2,
            errorStyle: const TextStyle(
              fontSize: 12,
              color: AuthColors.danger,
              fontWeight: FontWeight.w500,
            ),
            enabledBorder: _border(AuthColors.border, 1),
            disabledBorder: _border(AuthColors.border, 1),
            focusedBorder: _border(AuthColors.accent, 1.6),
            errorBorder: _border(AuthColors.danger, 1),
            focusedErrorBorder: _border(AuthColors.danger, 1.6),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Primary pill button with built-in loading state
// ─────────────────────────────────────────────────────────────────────────────
class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AuthColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: loading
              ? AuthColors.primary
              : Colors.grey.shade400,
          disabledForegroundColor: Colors.white,
          elevation: 4,
          shadowColor: const Color.fromRGBO(9, 44, 86, 0.35),
          shape: const StadiumBorder(),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Not you? Use another account" style footer link
// ─────────────────────────────────────────────────────────────────────────────
class AuthFooterLink extends StatelessWidget {
  final String prefix;
  final String action;
  final VoidCallback? onTap;

  const AuthFooterLink({
    super.key,
    required this.prefix,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 13.5, color: AuthColors.muted),
            children: [
              TextSpan(text: prefix),
              TextSpan(
                text: action,
                style: const TextStyle(
                  color: AuthColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OTP input: 6 boxes driven by ONE hidden text field.
// Gives paste, SMS autofill and backspace behavior for free.
// ─────────────────────────────────────────────────────────────────────────────
class OtpInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final ValueChanged<String>? onCompleted;

  const OtpInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.length = 6,
    this.enabled = true,
    this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                autofocus: true,
                showCursor: false,
                enableInteractiveSelection: false,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: length,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  if (v.length == length) onCompleted?.call(v);
                },
              ),
            ),
          ),
          IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, focusNode]),
              builder: (context, _) {
                final text = controller.text;
                final activeIndex = math.min(text.length, length - 1);
                return Row(
                  children: List.generate(length, (i) {
                    final filled = i < text.length;
                    final active =
                        focusNode.hasFocus && enabled && i == activeIndex;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: active
                                  ? AuthColors.accent
                                  : AuthColors.border,
                              width: active ? 1.8 : 1,
                            ),
                          ),
                          child: Text(
                            filled ? text[i] : '',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AuthColors.primary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}