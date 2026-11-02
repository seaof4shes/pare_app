import 'package:flutter/services.dart';
import '../../../services/app_update_service.dart';
import 'package:flutter/material.dart';

import 'package:pare_app/features/1_auth/screens/rings_painter.dart';
import 'package:pare_app/features/widgets/pare_shell.dart';

class UpdatesScreen extends StatefulWidget {
  final bool appUpdateAvailable;
  final bool smsModelUpdateAvailable;
  final bool voiceModelUpdateAvailable;

  final String installedAppVersion;
  final String latestAppVersion;

  final int installedSmsModelVersion;
  final int latestSmsModelVersion;

  final int installedVoiceModelVersion;
  final int latestVoiceModelVersion;

  const UpdatesScreen({
    super.key,
    required this.appUpdateAvailable,
    required this.smsModelUpdateAvailable,
    required this.voiceModelUpdateAvailable,
    required this.installedAppVersion,
    required this.latestAppVersion,
    required this.installedSmsModelVersion,
    required this.latestSmsModelVersion,
    required this.installedVoiceModelVersion,
    required this.latestVoiceModelVersion,
  });

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  static const Color primaryBlue = Color(0xFF092C56);
  static const Color heroBlue = Color(0xFF1B4F94);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color successColor = Color(0xFF1C8756);
  static const Color amberColor = Color(0xFFB9770E);

  static const Color dangerColor = Color(0xFFC0392B);

  bool get _hasUpdateInfo => widget.latestAppVersion.isNotEmpty;

  // ============================================================
  // PARE DIALOG HELPERS
  // Same visual style used by HomeScreen
  // ============================================================

  Dialog _pareDialogShell({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.fromLTRB(20, 28, 20, 16),
  }) {
    return Dialog(
      backgroundColor: surfaceColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(padding: padding, child: child),
      ),
    );
  }

  Widget _dialogPrimaryButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _dialogTextButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: mutedColor,
          ),
        ),
      ),
    );
  }

  Widget _alertIconBadge(IconData icon, Color color, {bool solid = false}) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: solid
          ? Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: 24, color: Colors.white),
            )
          : Icon(icon, size: 30, color: color),
    );
  }

  // ============================================================
  // UPDATE RESULT POPUP
  // ============================================================

  Future<void> _showUpdateDialog({
    required String title,
    required String message,
    required bool success,
    bool returnToHome = false,
  }) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _pareDialogShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _alertIconBadge(
                success
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                success ? successColor : dangerColor,
                solid: success,
              ),

              const SizedBox(height: 16),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: inkColor,
                  height: 1.25,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: mutedColor,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              _dialogPrimaryButton("Done", () {
                Navigator.pop(dialogContext);
              }),

              const SizedBox(height: 2),

              _dialogTextButton("Close", () {
                Navigator.pop(dialogContext);
              }),
            ],
          ),
        );
      },
    );

    if (returnToHome && mounted) {
      Navigator.pop(context, true);
    }
  }

  // ============================================================
  // APP UPDATE
  // ============================================================

  Future<void> _openAppUpdate() async {
    final latest = await AppUpdateService().getLatestUpdate();
    final url = latest?['appDownloadUrl']?.toString() ?? '';
    final uri = Uri.tryParse(url);
    if (!mounted) return;
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      await _showUpdateDialog(
        title: 'Installer not published',
        message:
            'The application version is listed, but its download link is not available yet. Contact the project administrator.',
        success: false,
      );
      return;
    }
    try {
      await const MethodChannel(
        'pare_app/block_sender',
      ).invokeMethod('openAppUpdate', {'url': url});
    } catch (_) {
      await _showUpdateDialog(
        title: 'Could not open installer',
        message: 'Please try again when a browser is available.',
        success: false,
      );
    }
  }

  // ============================================================
  // APP UPDATE PRESENTATION
  // ============================================================

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
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

  Widget _summaryHero(int count) {
    final bool allGood = _hasUpdateInfo && count == 0;

    final String title = !_hasUpdateInfo
        ? 'Update status unavailable'
        : count > 0
        ? '$count update${count > 1 ? 's' : ''} available'
        : 'Everything is up to date';

    final String subtitle = !_hasUpdateInfo
        ? 'Reconnect Wi-Fi or reopen Home to check again.'
        : count > 0
        ? 'A newer version of PARE is available.'
        : 'Your app is on the latest published version.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: allGood
              ? const [Color(0xFF0A3A47), Color(0xFF157A5B)]
              : const [primaryBlue, heroBlue],
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
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final updateCount = widget.appUpdateAvailable ? 1 : 0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PareHeader(
                title: 'Updates',
                subtitle: 'Application version and download',
                onBack: () => Navigator.pop(context),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryHero(updateCount),

                      // ------------------------------------------------
                      // APPLICATION UPDATE
                      // ------------------------------------------------
                      _sectionLabel('App'),
                      _updateCard(
                        icon: Icons.phone_android_rounded,
                        title: "PARE application",
                        currentVersion: widget.installedAppVersion,
                        latestVersion: widget.latestAppVersion,
                        description: widget.appUpdateAvailable
                            ? "A newer version of the PARE application is available."
                            : "Your PARE application is using the latest available version.",
                        buttonText: widget.appUpdateAvailable
                            ? "Download APK"
                            : "Up to Date",
                        onPressed: widget.appUpdateAvailable
                            ? _openAppUpdate
                            : null,
                        isAvailable: widget.appUpdateAvailable,
                      ),

                      // ------------------------------------------------
                      // DETECTION MODELS
                      // ------------------------------------------------
                      const SizedBox(height: 2),

                      // ------------------------------------------------
                      // INFORMATION
                      // ------------------------------------------------
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: accentBlue.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accentBlue.withValues(alpha: 0.15),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 19,
                              color: accentBlue,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Download the latest PARE APK, then open it and follow the Android installation prompts. Your confirmation is required. Detection improvements are included in app releases.",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: mutedColor,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

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

  // ============================================================
  // UPDATE CARD
  // ============================================================

  Widget _updateCard({
    required IconData icon,
    required String title,
    required String currentVersion,
    required String latestVersion,
    required String description,
    required String buttonText,
    required VoidCallback? onPressed,
    bool isLoading = false,
    required bool isAvailable,
  }) {
    final String pillText = !_hasUpdateInfo
        ? "Not checked"
        : isAvailable
        ? "Available"
        : "Up to date";

    final Color pillColor = !_hasUpdateInfo
        ? mutedColor
        : isAvailable
        ? amberColor
        : successColor;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accentBlue, size: 18),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: inkColor,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: pillColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pillText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: pillColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            _hasUpdateInfo
                ? description
                : 'Update information is unavailable. Reconnect Wi-Fi or reopen Home to check again.',
            style: const TextStyle(
              fontSize: 12.5,
              color: mutedColor,
              height: 1.35,
            ),
          ),

          // Version details are only shown when there is something to update.
          if (isAvailable) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _versionBox("Current", currentVersion)),
                const SizedBox(width: 10),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: mutedColor,
                ),
                const SizedBox(width: 10),
                Expanded(child: _versionBox("Latest", latestVersion)),
              ],
            ),
          ] else if (currentVersion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Version $currentVersion',
              style: const TextStyle(fontSize: 11.5, color: mutedColor),
            ),
          ],

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: isAvailable
                    ? primaryBlue
                    : successColor.withValues(alpha: 0.12),
                foregroundColor: isAvailable ? Colors.white : successColor,
                disabledBackgroundColor: isAvailable
                    ? primaryBlue.withValues(alpha: 0.45)
                    : successColor.withValues(alpha: 0.12),
                disabledForegroundColor: isAvailable
                    ? Colors.white
                    : successColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _hasUpdateInfo ? buttonText : 'Not checked',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // VERSION BOX
  // ============================================================

  Widget _versionBox(String label, String version) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: mutedColor,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            version.isEmpty ? 'Unavailable' : version,
            style: const TextStyle(
              fontSize: 14,
              color: inkColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
