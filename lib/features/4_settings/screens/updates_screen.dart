import 'package:flutter/material.dart';

import '../../../core/ml/sms_detection_service.dart';
import '../../../core/ml/voice_detection_service.dart';

import 'dart:developer';

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
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color successColor = Color(0xFF1C8756);

  static const Color dangerColor = Color(0xFFC0392B);

  bool _isUpdatingSmsModel = false;
  bool _isUpdatingVoiceModel = false;

  // ============================================================
  // P.A.R.E. DIALOG HELPERS
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
  // SMS MODEL UPDATE
  // ============================================================

  Future<void> _updateSmsModel() async {
    if (_isUpdatingSmsModel) return;

    setState(() {
      _isUpdatingSmsModel = true;
    });

    try {
      final smsService = SmsDetectionService();

      final result = await smsService.downloadAndInstallModel(
        storagePath:
            'updates/models/sms_scam_model_v${widget.latestSmsModelVersion}.tflite',
        modelVersion: widget.latestSmsModelVersion,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await _showUpdateDialog(
          title: "SMS Model Updated",
          message:
              "SMS Detection Model v${widget.latestSmsModelVersion} "
              "has been successfully installed and is now active.",
          success: true,
          returnToHome: true,
        );
      } else {
        await _showUpdateDialog(
          title: "Update Failed",
          message:
              result['error']?.toString() ??
              "The SMS detection model could not be updated. "
                  "Your current model will continue to be used.",
          success: false,
        );
      }
    } catch (e) {
      if (!mounted) return;

      await _showUpdateDialog(
        title: "Update Failed",
        message:
            "The SMS detection model could not be updated. "
            "Your current model will continue to be used.",
        success: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingSmsModel = false;
        });
      }
    }
  }

  // ============================================================
  // VOICE MODEL UPDATE
  // ============================================================

  Future<void> _updateVoiceModel() async {
    if (_isUpdatingVoiceModel) return;

    setState(() {
      _isUpdatingVoiceModel = true;
    });

    log('🎤 BUTTON: Update Voice Model pressed.');

    try {
      final voiceService = VoiceDetectionService();

      log('🎤 SERVICE: VoiceDetectionService created.');

      final storagePath =
          'updates/models/voice_model_v${widget.latestVoiceModelVersion}.tflite';

      log('📦 STORAGE PATH: $storagePath');
      log('🎤 TARGET VERSION: ${widget.latestVoiceModelVersion}');

      log('☁️ STARTING VOICE MODEL DOWNLOAD...');

      final success = await voiceService.downloadAndInstallModel(
        storagePath: storagePath,
        modelVersion: widget.latestVoiceModelVersion,
      );

      log('🎤 DOWNLOAD/INSTALL RESULT: $success');

      if (!mounted) return;

      if (success) {
        log('✅ VOICE MODEL UPDATE SUCCESS.');

        await _showUpdateDialog(
          title: "Voice Model Updated",
          message:
              "Voice Detection Model v${widget.latestVoiceModelVersion} "
              "has been successfully installed and is now active.",
          success: true,
          returnToHome: true,
        );

        log('🏠 RETURNING TO HOME AFTER VOICE UPDATE.');
      } else {
        log('❌ VOICE MODEL UPDATE RETURNED FALSE.');

        await _showUpdateDialog(
          title: "Update Failed",
          message:
              "The voice detection model could not be updated. "
              "Your current model will continue to be used.",
          success: false,
        );
      }
    } catch (e, stackTrace) {
      log('❌ VOICE MODEL UPDATE ERROR: $e');
      log('❌ STACK TRACE: $stackTrace');

      if (!mounted) return;

      await _showUpdateDialog(
        title: "Update Failed",
        message:
            "The voice detection model could not be updated. "
            "Your current model will continue to be used.",
        success: false,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingVoiceModel = false;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final hasUpdates =
        widget.appUpdateAvailable ||
        widget.smsModelUpdateAvailable ||
        widget.voiceModelUpdateAvailable;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: primaryBlue,
        title: const Text(
          "Updates",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasUpdates ? "Updates Available" : "P.A.R.E. Status",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: inkColor,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                hasUpdates
                    ? "Newer application or detection models are available."
                    : "Your application and detection models are up to date.",
                style: const TextStyle(fontSize: 13, color: mutedColor),
              ),

              const SizedBox(height: 20),

              // ------------------------------------------------------------
              // APPLICATION UPDATE
              // ------------------------------------------------------------
              _updateCard(
                icon: Icons.phone_android_rounded,
                title: "P.A.R.E. Application",
                currentVersion: widget.installedAppVersion,
                latestVersion: widget.latestAppVersion,
                description: widget.appUpdateAvailable
                    ? "A newer version of the P.A.R.E. application is available."
                    : "Your P.A.R.E. application is using the latest available version.",
                buttonText: widget.appUpdateAvailable
                    ? "Update Application"
                    : "Up to Date",
                onPressed: null,
                isAvailable: widget.appUpdateAvailable,
              ),

              // ------------------------------------------------------------
              // SMS DETECTION MODEL
              // ------------------------------------------------------------
              _updateCard(
                icon: Icons.sms_outlined,
                title: "SMS Detection Model",
                currentVersion: "v${widget.installedSmsModelVersion}",
                latestVersion: "v${widget.latestSmsModelVersion}",
                description: widget.smsModelUpdateAvailable
                    ? "An improved SMS scam detection model is available."
                    : "Your SMS scam detection model is using the latest available version.",
                buttonText: widget.smsModelUpdateAvailable
                    ? (_isUpdatingSmsModel
                          ? "Updating SMS Model..."
                          : "Update SMS Model")
                    : "Up to Date",
                onPressed: widget.smsModelUpdateAvailable
                    ? (_isUpdatingSmsModel ? null : _updateSmsModel)
                    : null,
                isLoading: _isUpdatingSmsModel,
                isAvailable: widget.smsModelUpdateAvailable,
              ),

              // ------------------------------------------------------------
              // VOICE DETECTION MODEL
              // ------------------------------------------------------------
              _updateCard(
                icon: Icons.graphic_eq_rounded,
                title: "Voice Detection Model",
                currentVersion: "v${widget.installedVoiceModelVersion}",
                latestVersion: "v${widget.latestVoiceModelVersion}",
                description: widget.voiceModelUpdateAvailable
                    ? "A newer voice detection model is available."
                    : "Your voice detection model is using the latest available version.",
                buttonText: widget.voiceModelUpdateAvailable
                    ? (_isUpdatingVoiceModel
                          ? "Updating Voice Model..."
                          : "Update Voice Model")
                    : "Up to Date",
                onPressed: widget.voiceModelUpdateAvailable
                    ? (_isUpdatingVoiceModel ? null : _updateVoiceModel)
                    : null,
                isLoading: _isUpdatingVoiceModel,
                isAvailable: widget.voiceModelUpdateAvailable,
              ),

              const SizedBox(height: 2),

              // ------------------------------------------------------------
              // INFORMATION BOX
              // ------------------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.15),
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
                        "Updates are optional. Your current application and detection models will continue to work until you choose to update them.",
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryBlue, size: 21),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: inkColor,
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? accentBlue.withValues(alpha: 0.10)
                      : successColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAvailable ? "Available" : "Up to Date",
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isAvailable ? accentBlue : successColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            description,
            style: const TextStyle(
              fontSize: 12.5,
              color: mutedColor,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 14),

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

          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            height: 44,
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
                  borderRadius: BorderRadius.circular(11),
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
                      buttonText,
                      style: const TextStyle(
                        fontSize: 13,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

          const SizedBox(height: 3),

          Text(
            version,
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
