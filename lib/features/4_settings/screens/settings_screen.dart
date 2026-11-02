import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../../services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/features/1_auth/screens/login_screen.dart';
import 'package:pare_app/features/1_auth/screens/rings_painter.dart';
import 'package:pare_app/features/widgets/pare_shell.dart';
import 'package:app_settings/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onSettingsChanged});
  final VoidCallback? onSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ---------------------------------------------------------------------
  // Design tokens — shared with HomeScreen / HistoryScreen.
  // ---------------------------------------------------------------------
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color heroBlue = Color(0xFF1B4F94);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color dividerColor = Color(0xFFEDF1F6);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color dangerColor = Color(0xFFC0392B);
  static const Color amberColor = Color(0xFFB9770E);

  // ---------------------------------------------------------------------
  // Existing preference keys are preserved for compatibility with the
  // rest of the application.
  // ---------------------------------------------------------------------
  static const String keyMsgDetection = 'msg_detection';
  static const String keyMsgScamAlerts = 'msg_scam_alerts';
  static const String keyNotifSound = 'notif_sound';
  static const String keyNotifVibrate = 'notif_vibrate';

  // ---------------------------------------------------------------------
  // Settings state
  // ---------------------------------------------------------------------
  bool protectVoice = true;
  bool protectSMS = true;
  bool msgScamAlerts = true;

  bool notifSound = true;
  bool notifVibrate = true;

  bool _isLoading = true;
  bool _isLoggingOut = false;

  String _username = "Username";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ---------------------------------------------------------------------
  // Load saved settings  (UNCHANGED)
  // ---------------------------------------------------------------------

  Future<void> _loadSettings() async {
    final prefs = await PrivatePreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _username = prefs.getString('username') ?? "Username";
      protectVoice = prefs.getBool('call_detection') ?? true;

      // Keep the existing 'call_detection' key so other parts of the
      // application that already use it remain compatible.

      protectSMS = prefs.getBool(keyMsgDetection) ?? true;

      msgScamAlerts = prefs.getBool(keyMsgScamAlerts) ?? true;

      notifSound = prefs.getBool(keyNotifSound) ?? true;
      notifVibrate = prefs.getBool(keyNotifVibrate) ?? true;

      _isLoading = false;
    });
  }

  // ---------------------------------------------------------------------
  // Save boolean preference  (UNCHANGED)
  // ---------------------------------------------------------------------

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await PrivatePreferences.getInstance();
      if (!await prefs.setBool(key, value)) {
        throw StateError('Preference not saved');
      }
      widget.onSettingsChanged?.call();
    } catch (_) {
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setting could not be saved. Please try again.'),
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Logout  (UNCHANGED)
  // ---------------------------------------------------------------------

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      final prefs = await PrivatePreferences.getInstance();

      await prefs.setBool('protection_activated', false);
      await FirebaseAuth.instance.signOut();
      try {
        await NotificationService.clearForLogout();
      } on PlatformException {
        // Session removal must still complete if Android notification cleanup fails.
      }
      try {
        await const MethodChannel(
          'pare_app/block_sender',
        ).invokeMethod('clearPendingSms');
      } on PlatformException {
        /* Protection is already disabled. */
      }

      // Clear the active session
      await prefs.remove('phone');
      await prefs.remove('username');
      await prefs.remove('pending_login_phone');

      // Require OTP on the next login
      await prefs.setBool('requireOtp', true);
      await prefs.setBool('isLoggedIn', false);

      // Turn off active protection
      await prefs.setBool('protection_activated', false);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not finish signing out. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  // ---------------------------------------------------------------------
  // Open Android application settings  (UNCHANGED)
  // ---------------------------------------------------------------------

  Future<void> _openAppSettings() async {
    await AppSettings.openAppSettings();
  }

  // ---------------------------------------------------------------------
  // NEW (UI only): ask before logging out, then run the same _logout().
  // To remove the confirmation, point the button's onPressed straight at
  // _logout instead of _confirmLogout.
  // ---------------------------------------------------------------------

  Future<void> _confirmLogout() async {
    if (_isLoggingOut) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
        decoration: const BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: dangerColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: dangerColor,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Log out of PARE?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: inkColor,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Protection will turn off and you'll need an OTP to log in next time.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: mutedColor, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dangerColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Log out',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  style: TextButton.styleFrom(
                    backgroundColor: backgroundColor,
                    foregroundColor: inkColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  // ---------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------

  Widget _header() {
    return PareHeader(
      title: 'PARE',
      subtitle: 'Manage protection',
      username: _username,
    );
  }

  // ---------------------------------------------------------------------
  // Status hero (UI only — reads the existing switch values)
  // ---------------------------------------------------------------------

  Widget _statusHero() {
    final alertsActive = msgScamAlerts && protectSMS;

    final active = [protectVoice, protectSMS, alertsActive];
    final count = active.where((e) => e).length;

    final Color ringColor = count == 3
        ? const Color(0xFF6FE3A5)
        : count == 0
        ? const Color(0xFFFF8F84)
        : const Color(0xFFFFD27A);

    final String title = count == 3
        ? 'Fully protected'
        : count == 0
        ? 'Protection is off'
        : 'Partly protected';

    final String subtitle = count == 3
        ? 'Voice, messages and alerts are all on.'
        : count == 0
        ? 'Turn something on to stay safe from scams.'
        : '${3 - count} of 3 protections are off.';

    Widget chip(String label, bool on) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on
                      ? const Color(0xFF6FE3A5)
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
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
              right: -66,
              top: -76,
              child: CustomPaint(size: Size(200, 200), painter: RingsPainter()),
            ),
            Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: count / 3),
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => CustomPaint(
                              size: const Size(64, 64),
                              painter: _ProgressRingPainter(
                                progress: value,
                                color: ringColor,
                              ),
                            ),
                          ),
                          Text(
                            '$count/3',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    chip('Voice', protectVoice),
                    const SizedBox(width: 6),
                    chip('Messages', protectSMS),
                    const SizedBox(width: 6),
                    chip('Alerts', alertsActive),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Section label + grouped card
  // ---------------------------------------------------------------------

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: mutedColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// One white card; rows are separated by thin dividers.
  Widget _group(List<Widget> rows) {
    final children = <Widget>[];

    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i < rows.length - 1) {
        children.add(
          const Divider(height: 1, thickness: 1, color: dividerColor),
        );
      }
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: children),
    );
  }

  Widget _iconTile(IconData icon, {required bool on, Color tint = accentBlue}) {
    final color = on ? tint : const Color(0xFF98A2B0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? tint.withValues(alpha: 0.10) : const Color(0xFFEEF1F5),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color tint = accentBlue,
    bool nested = false,
    bool dimmed = false,
  }) {
    final row = Padding(
      padding: EdgeInsets.fromLTRB(nested ? 46 : 14, 13, 14, 13),
      child: Row(
        children: [
          _iconTile(icon, on: value && !dimmed, tint: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: inkColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PareSwitch(value: value, onChanged: onChanged, label: title),
        ],
      ),
    );

    if (!nested) return row;

    // Connector line linking the nested row to the row above it.
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          row,
          Positioned(
            left: 31,
            top: -4,
            child: Container(
              width: 12,
              height: 30,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFFD5DCE6), width: 2),
                  bottom: BorderSide(color: Color(0xFFD5DCE6), width: 2),
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(9)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return InkWell(
      onTap: _openAppSettings,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            _iconTile(icon, on: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: inkColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: mutedColor,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFB3BCC9),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.shield_outlined,
              size: 19,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PARE',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: inkColor,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Version 1.0 · Capstone project',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: TextButton.icon(
        onPressed: _isLoggingOut ? null : _confirmLogout,
        icon: _isLoggingOut
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: dangerColor,
                ),
              )
            : const Icon(Icons.logout_rounded, size: 18),
        label: const Text(
          'Log out',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
        style: TextButton.styleFrom(
          foregroundColor: dangerColor,
          backgroundColor: dangerColor.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),

              const SizedBox(height: 16),

              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: primaryBlue),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _statusHero(),

                            // =============================================
                            // PROTECTION
                            // =============================================
                            _sectionLabel('Protection'),
                            _group([
                              _switchRow(
                                icon: Icons.mic_none_outlined,
                                title: 'Voice detection',
                                subtitle: 'Record, upload and check calls',
                                value: protectVoice,
                                onChanged: (v) {
                                  setState(() {
                                    protectVoice = v;
                                  });
                                  _saveBool('call_detection', v);
                                },
                              ),

                              _switchRow(
                                icon: Icons.sms_outlined,
                                title: 'Message detection',
                                subtitle: 'Scan incoming texts for scams',
                                value: protectSMS,
                                onChanged: (v) {
                                  setState(() {
                                    protectSMS = v;
                                  });

                                  _saveBool(keyMsgDetection, v);
                                },
                              ),

                              _switchRow(
                                icon: Icons.warning_amber_rounded,
                                title: 'Scam alerts',
                                subtitle: protectSMS
                                    ? 'Warn on medium and high risk'
                                    : 'Turn on message detection first',
                                value: msgScamAlerts,
                                tint: amberColor,
                                nested: true,
                                dimmed: !protectSMS,
                                onChanged: (v) {
                                  setState(() {
                                    msgScamAlerts = v;
                                  });

                                  _saveBool(keyMsgScamAlerts, v);
                                },
                              ),
                            ]),

                            // =============================================
                            // NOTIFICATIONS
                            // =============================================
                            _sectionLabel('Notifications'),
                            _group([
                              _switchRow(
                                icon: Icons.volume_up_outlined,
                                title: 'Sound',
                                subtitle: 'Play a sound on scam alerts',
                                value: notifSound,
                                onChanged: (v) {
                                  setState(() {
                                    notifSound = v;
                                  });

                                  _saveBool(keyNotifSound, v);
                                },
                              ),

                              _switchRow(
                                icon: Icons.vibration_outlined,
                                title: 'Vibration',
                                subtitle: 'Vibrate during scam warnings',
                                value: notifVibrate,
                                onChanged: (v) {
                                  setState(() {
                                    notifVibrate = v;
                                  });

                                  _saveBool(keyNotifVibrate, v);
                                },
                              ),
                            ]),

                            // =============================================
                            // PRIVACY & PERMISSIONS
                            // =============================================
                            _sectionLabel('Privacy and permissions'),
                            _group([
                              _permissionRow(
                                icon: Icons.sms_outlined,
                                title: 'Incoming messages',
                                subtitle: 'Needed to detect scam texts',
                              ),
                              _permissionRow(
                                icon: Icons.mic_none_outlined,
                                title: 'Microphone',
                                subtitle: 'For supported voice analysis',
                              ),
                              _permissionRow(
                                icon: Icons.upload_file_outlined,
                                title: 'Files',
                                subtitle: 'For uploading voice recordings',
                              ),
                            ]),

                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                              child: Text(
                                "Tap a permission to open your phone's app settings.",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: mutedColor,
                                ),
                              ),
                            ),

                            // =============================================
                            // ABOUT
                            // =============================================
                            _sectionLabel('About'),
                            _group([_aboutRow()]),

                            const SizedBox(height: 22),

                            _logoutButton(),

                            const SizedBox(height: 24),
                          ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Small custom switch (same behavior as Switch: value + onChanged).
// ─────────────────────────────────────────────────────────────────────────────

class _PareSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  const _PareSwitch({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: 46,
            height: 27,
            padding: const EdgeInsets.all(3),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value
                  ? _SettingsScreenState.primaryBlue
                  : const Color(0xFFD5DCE6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Container(
              width: 21,
              height: 21,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress ring for the status card.
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressRingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;

  const _ProgressRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.18);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    if (progress > 0) {
      canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.progress != progress || old.color != color;
}
