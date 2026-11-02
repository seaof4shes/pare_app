import '../../../services/sms_processing_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pare_app/core/security/private_preferences.dart';

import 'package:pare_app/services/notification_service.dart';
import 'package:pare_app/services/app_update_service.dart';

import 'package:pare_app/core/database/database_helper.dart';
import 'package:pare_app/core/permissions/permission_service.dart';
import 'package:pare_app/core/ml/sms_detection_service.dart';
import 'package:pare_app/core/ml/call_detection_service.dart';

import 'package:pare_app/features/4_settings/screens/updates_screen.dart';
import 'package:pare_app/features/3_history/screens/history_screen.dart';
import 'package:pare_app/features/3_history/widgets/history_presentation.dart';
import 'package:pare_app/features/1_auth/screens/rings_painter.dart';
import 'package:pare_app/features/widgets/pare_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final SmsDetectionService smsModel = SmsDetectionService();

  // Kept for the current working voice implementation.
  // This service currently handles the recording/upload analysis flow.
  final CallDetectionService callDetectionService = CallDetectionService();

  static const EventChannel smsEventChannel = EventChannel(
    'pare_app/sms_receiver',
  );

  StreamSubscription? _smsSubscription;

  // ============================================================
  // DESIGN TOKENS
  // ============================================================

  static const Color primaryBlue = Color(0xFF092C56);
  static const Color heroBlue = Color(0xFF1B4F94);
  static const Color accentBlue = Color(0xFF2A5298);
  static const Color backgroundColor = Color(0xFFF6F8FB);
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color borderColor = Color(0xFFE4E9F0);
  static const Color dividerColor = Color(0xFFEDF1F6);
  static const Color inkColor = Color(0xFF10192B);
  static const Color mutedColor = Color(0xFF6B7686);
  static const Color successColor = Color(0xFF1C8756);
  static const Color warningColor = Color(0xFFB9770E);
  static const Color dangerColor = Color(0xFFC0392B);
  static const Color tintBlue = Color.fromRGBO(9, 44, 86, 0.07);
  static const Color softBlue = Color(0xFFE8EEF8);

  static const String _prefKey = 'protection_activated';

  static const String keyCallDetection = 'call_detection';
  static const String keyMsgDetection = 'msg_detection';
  static const String keyMsgScamAlerts = 'msg_scam_alerts';

  bool _isActivated = false;
  bool _isLoading = true;

  bool _smsListenerStarted = false;
  bool _callListenerStarted = false;

  bool _callDetection = true;
  bool _msgDetection = true;
  bool _msgScamAlerts = true;
  bool get _smsAlertsActive => _isActivated && _msgDetection && _msgScamAlerts;

  bool _isRecordingVoice = false;
  bool _isUploadingVoice = false;

  String _username = "Username";

  // Recent detections shown on Home (read-only view of History).
  List<Map<String, dynamic>> _recent = [];

  // Drives the soft pulse rings around the shield button.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  // ============================================================
  // UPDATE STATE
  // ============================================================

  bool _updateAvailable = false;
  bool _appUpdateAvailable = false;
  bool _smsModelUpdateAvailable = false;
  bool _voiceModelUpdateAvailable = false;

  String _installedAppVersion = '';
  String _latestAppVersion = '';

  int _installedSmsModelVersion = 1;
  int _latestSmsModelVersion = 1;

  int _installedVoiceModelVersion = 4;
  int _latestVoiceModelVersion = 4;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // UI only: lets the shared header bell open the Updates screen.
    PareUpdateStatus.instance.openUpdates = _openUpdatesScreen;

    initializeApp();
  }

  Future<void> refreshHomeSettings() async {
    await _loadState();
  }

  Future<void> refreshUpdateStatus() => _checkForUpdates();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadState();
    if (state == AppLifecycleState.paused) _stopCallDetection();
  }

  Future<void> initializeApp() async {
    await _loadState();
    await initModel();

    await _checkForUpdates();
  }

  // ============================================================
  // UPDATE CHECK
  // ============================================================

  Future<void> _checkForUpdates() async {
    debugPrint('🔍 Home: Checking for PARE updates...');

    try {
      final updateService = AppUpdateService();

      final result = await updateService.checkForUpdates();

      if (result['success'] != true) {
        if (!mounted) return;
        setState(() {
          _installedAppVersion =
              result['installedAppVersion']?.toString() ?? _installedAppVersion;
          _latestAppVersion = '';
          _appUpdateAvailable = false;
          _updateAvailable = false;
        });
        PareUpdateStatus.instance.available.value = false;
        debugPrint('⚠️ Home update check was unsuccessful.');
        debugPrint('⚠️ Error: ${result['error']}');
        return;
      }

      if (!mounted) return;

      setState(() {
        _updateAvailable = result['appUpdateAvailable'] == true;

        _appUpdateAvailable = result['appUpdateAvailable'] == true;

        _smsModelUpdateAvailable = result['smsModelUpdateAvailable'] == true;

        _voiceModelUpdateAvailable =
            result['voiceModelUpdateAvailable'] == true;

        _installedAppVersion = result['installedAppVersion']?.toString() ?? '';

        _latestAppVersion = result['latestAppVersion']?.toString() ?? '';

        _installedSmsModelVersion = _toInt(result['installedSmsModelVersion']);

        _latestSmsModelVersion = _toInt(result['latestSmsModelVersion']);

        _installedVoiceModelVersion = _toInt(
          result['installedVoiceModelVersion'],
        );

        _latestVoiceModelVersion = _toInt(result['latestVoiceModelVersion']);
      });

      // UI only: tell the shared header bell about the update status.
      PareUpdateStatus.instance.available.value = _updateAvailable;

      debugPrint('🔔 Home update available: $_updateAvailable');
      debugPrint('📱 App update: $_appUpdateAvailable');
      debugPrint('📩 SMS model update: $_smsModelUpdateAvailable');
      debugPrint('🎤 Voice model update: $_voiceModelUpdateAvailable');
    } catch (e, stackTrace) {
      debugPrint('❌ Home update check failed: $e');
      debugPrint('$stackTrace');
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _openUpdatesScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UpdatesScreen(
          appUpdateAvailable: _appUpdateAvailable,
          smsModelUpdateAvailable: _smsModelUpdateAvailable,
          voiceModelUpdateAvailable: _voiceModelUpdateAvailable,
          installedAppVersion: _installedAppVersion,
          latestAppVersion: _latestAppVersion,
          installedSmsModelVersion: _installedSmsModelVersion,
          latestSmsModelVersion: _latestSmsModelVersion,
          installedVoiceModelVersion: _installedVoiceModelVersion,
          latestVoiceModelVersion: _latestVoiceModelVersion,
        ),
      ),
    );

    await _checkForUpdates();
  }

  // ============================================================
  // MODEL
  // ============================================================

  Future<void> initModel() async {
    try {
      await smsModel.loadModel();

      if (!mounted) return;

      debugPrint("✅ SMS model loaded");
    } catch (e) {
      debugPrint("❌ Model error: $e");
    }
  }

  // ============================================================
  // STATE
  // ============================================================

  Future<void> _loadState() async {
    final prefs = await PrivatePreferences.getInstance();

    final activated = prefs.getBool(_prefKey) ?? false;

    final savedUsername = prefs.getString('username') ?? "Username";

    final callDetection = prefs.getBool(keyCallDetection) ?? true;

    final msgDetection = prefs.getBool(keyMsgDetection) ?? true;

    final msgScamAlerts = prefs.getBool(keyMsgScamAlerts) ?? true;

    if (!mounted) return;

    setState(() {
      _username = savedUsername;
      _isActivated = activated;
      _callDetection = callDetection;
      _msgDetection = msgDetection;
      _msgScamAlerts = msgScamAlerts;
      _isLoading = false;
    });

    // UI only: refresh the "Recent activity" list.
    _loadRecentActivity();

    if (!_isActivated) {
      await _stopSmsListener();
      await _stopCallDetection();
      return;
    }

    if (_msgDetection) {
      await startSmsListener();
    } else {
      await _stopSmsListener();
    }

    if (_callDetection) {
      await startCallDetection();
    } else {
      await _stopCallDetection();
    }
  }

  // ============================================================
  // RECENT ACTIVITY (read-only, UI only)
  // ============================================================

  Future<void> _loadRecentActivity() async {
    try {
      final prefs = await PrivatePreferences.getInstance();
      final phone = prefs.getString('phone') ?? '';

      final rows = await DatabaseHelper.instance.getHistory(userPhone: phone);

      final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();

      // Newest first (ISO-8601 strings sort correctly as text).
      list.sort(
        (a, b) => (b['dateTime']?.toString() ?? '').compareTo(
          a['dateTime']?.toString() ?? '',
        ),
      );

      if (!mounted) return;

      setState(() => _recent = list.take(3).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _recent = []);
    }
  }

  String _recentSender(dynamic raw) {
    final s = raw?.toString().trim() ?? '';

    if (s.isEmpty) return 'Unknown sender';
    if (s.contains(RegExp(r'[a-zA-Z]'))) return s;

    final digits = s.replaceAll(RegExp(r'\D'), '');

    if (digits.length == 10 && digits.startsWith('9')) {
      return '+63 ${digits.substring(0, 3)} '
          '${digits.substring(3, 6)} ${digits.substring(6)}';
    } else if (digits.length == 11 && digits.startsWith('09')) {
      return '+63 ${digits.substring(1, 4)} '
          '${digits.substring(4, 7)} ${digits.substring(7)}';
    } else if (digits.length == 12 && digits.startsWith('63')) {
      return '+63 ${digits.substring(2, 5)} '
          '${digits.substring(5, 8)} ${digits.substring(8)}';
    }

    return s;
  }

  String _recentWhen(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '');

    if (date == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) {
      final hour = date.hour > 12
          ? date.hour - 12
          : date.hour == 0
          ? 12
          : date.hour;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }

    if (diff == 1) return 'Yesterday';

    return '${date.month}/${date.day}/${date.year}';
  }

  // ============================================================
  // SMS LISTENER
  // ============================================================

  Future<void> startSmsListener() async {
    if (_smsListenerStarted) return;

    final status = await Permission.sms.request();

    if (!status.isGranted) {
      debugPrint("❌ SMS permission denied");
      return;
    }

    _smsListenerStarted = true;

    _smsSubscription = smsEventChannel.receiveBroadcastStream().listen(
      (event) async {
        final data = Map<String, dynamic>.from(event);

        final senderNumber = data['senderNumber']?.toString() ?? 'Unknown';

        final senderName = data['senderName']?.toString() ?? '';

        final smsBody = data['body']?.toString() ?? '';

        final sender = senderName.isNotEmpty ? senderName : senderNumber;

        debugPrint("📩 NATIVE SMS RECEIVED");

        if (smsBody.isEmpty) return;

        final prefs = await PrivatePreferences.getInstance();

        final activated = prefs.getBool(_prefKey) ?? false;

        final msgDetection = prefs.getBool(keyMsgDetection) ?? true;

        if (data['owner'] != null &&
            data['owner'] != (prefs.getString('phone') ?? '') &&
            data['owner'] != prefs.getString('sms_owner')) {
          await const MethodChannel(
            'pare_app/block_sender',
          ).invokeMethod('acknowledgeSms', {'id': data['id']});
          return;
        }
        if (!activated) {
          if (data['id'] != null) {
            await const MethodChannel(
              'pare_app/block_sender',
            ).invokeMethod('acknowledgeSms', {'id': data['id']});
          }
          debugPrint("Protection is OFF. Skipping SMS detection.");
          return;
        }

        if (!msgDetection) {
          if (data['id'] != null) {
            await const MethodChannel(
              'pare_app/block_sender',
            ).invokeMethod('acknowledgeSms', {'id': data['id']});
          }
          debugPrint(
            "Message Detection is OFF. "
            "Skipping SMS detection.",
          );
          return;
        }

        final saved = await detectIncomingSms(
          owner: data['owner']?.toString(),
          deliveryId: data['id']?.toString(),
          receivedAt: (data['receivedAt'] as num?)?.toInt(),
          message: smsBody,
          sender: sender,
          senderNumber: senderNumber,
        );
        if (saved && data['id'] != null) {
          await const MethodChannel(
            'pare_app/block_sender',
          ).invokeMethod('acknowledgeSms', {'id': data['id']});
        }
      },
      onError: (error) {
        debugPrint("❌ Native SMS listener error: $error");
      },
    );

    debugPrint("✅ Native SMS listener started");
  }

  Future<void> _stopSmsListener() async {
    if (!_smsListenerStarted) return;

    await _smsSubscription?.cancel();

    _smsSubscription = null;
    _smsListenerStarted = false;

    debugPrint("🛑 SMS listener stopped");
  }

  // ============================================================
  // AUDIO DETECTION
  // ============================================================

  Future<void> startCallDetection() async {
    if (!_isActivated || !_callDetection) {
      return;
    }

    if (_callListenerStarted) return;

    try {
      await callDetectionService.start();

      _callListenerStarted = true;

      debugPrint("🎤 Audio detection is enabled and ready.");
    } catch (e) {
      debugPrint("❌ Audio detection error: $e");
    }
  }

  Future<void> _stopCallDetection() async {
    if (!_callListenerStarted) return;

    await callDetectionService.stop();

    _callListenerStarted = false;

    debugPrint("🛑 Audio detection stopped from Home");
  }

  // ============================================================
  // SMS DETECTION
  // ============================================================

  Future<bool> detectIncomingSms({
    required String? owner,
    String? deliveryId,
    int? receivedAt,
    required String message,
    required String sender,
    required String senderNumber,
  }) async {
    try {
      return await SmsProcessingService(smsModel).process({
        'id': deliveryId,
        'receivedAt': receivedAt,
        'body': message,
        'senderName': sender,
        'senderNumber': senderNumber,
        'owner': owner,
      });
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // VOICE / AUDIO HISTORY
  // ============================================================

  Future<int> saveVoiceToHistory({
    required Map result,
    required String source,
    String? fileName,
  }) async {
    final prefs = await PrivatePreferences.getInstance();

    final currentPhone = prefs.getString('phone') ?? '';

    final label = result['label']?.toString() ?? 'Unknown';

    var confidence =
        double.tryParse(result['confidence']?.toString() ?? '') ?? 0.0;

    // Voice history stores confidence as 0-100.
    if (confidence <= 1.0) {
      confidence *= 100;
    }

    confidence = confidence.clamp(0.0, 100.0).toDouble();

    final lower = label.toLowerCase();

    final isHuman = lower.contains('human');

    final isSynthetic =
        !lower.contains('possible') &&
        !lower.contains('suspicious') &&
        (RegExp(r'\bai\b').hasMatch(lower) ||
            lower.contains('deepfake') ||
            lower.contains('synthetic'));

    final isSuspicious =
        lower.contains('suspicious') || lower.contains('possible');

    final riskLevel = isSuspicious
        ? 'MEDIUM'
        : isSynthetic
        ? 'HIGH'
        : isHuman
        ? 'LOW'
        : 'UNKNOWN';

    final safe = isHuman && !isSynthetic && !isSuspicious;

    // Current audio behavior:
    // Human Voice -> Allowed
    // Suspicious / Possible AI -> Alert Shown
    // AI / Deepfake -> Alert Shown
    final action = 'Analysis shown';

    final id = await DatabaseHelper.instance.insertHistory({
      'userPhone': currentPhone,
      'name': fileName ?? 'Recorded Sample',
      'senderNumber': source == 'Recorded Sample'
          ? 'Microphone Sample'
          : 'Uploaded File',
      'type': 'Audio',
      'message': 'Voice analysis result: $label',
      'result': label,
      'confidence': confidence,
      'action': action,
      'category': 'Audio',
      'safe': safe ? 1 : 0,
      'keywordScore': 0,
      'riskLevel': riskLevel,
      'dateTime': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Saved voice analysis to SQLite history with ID: $id');

    // UI only: show the new record under "Recent activity".
    _loadRecentActivity();

    return id;
  }

  // ============================================================
  // PARE POPUP HELPERS
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

  Widget _statusPill(String text, bool isOn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isOn
            ? successColor.withValues(alpha: 0.10)
            : Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isOn ? successColor : mutedColor,
        ),
      ),
    );
  }

  Widget _alertRows(List<_AlertRow> rows) {
    final hasBadges = rows.any((row) => row.badge != null);

    if (hasBadges) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      rows[i].icon,
                      size: 18,
                      color: rows[i].badgeOn ? accentBlue : mutedColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        rows[i].label,
                        style: const TextStyle(fontSize: 14, color: inkColor),
                      ),
                    ),
                    if (rows[i].badge != null)
                      _statusPill(rows[i].badge!, rows[i].badgeOn),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            children: [
              _iconBadge(rows[i].icon),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  rows[i].label,
                  style: const TextStyle(fontSize: 14, color: inkColor),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ============================================================
  // PARE ALERT POPUP
  // ============================================================

  Future<void> _showPAREAlert({
    required String title,
    required String message,
    IconData icon = Icons.info_outline,
    Color iconColor = primaryBlue,
    String buttonText = "OK",
    VoidCallback? onButtonPressed,
    String? secondaryButtonText,
    bool solidIcon = false,
    List<_AlertRow> rows = const [],
  }) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return _pareDialogShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _alertIconBadge(icon, iconColor, solid: solidIcon),
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
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 18),
                _alertRows(rows),
              ],
              const SizedBox(height: 20),
              _dialogPrimaryButton(buttonText, () {
                Navigator.pop(dialogContext);
                onButtonPressed?.call();
              }),
              if (secondaryButtonText != null) ...[
                const SizedBox(height: 2),
                _dialogTextButton(
                  secondaryButtonText,
                  () => Navigator.pop(dialogContext),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // VOICE RESULT DIALOG
  // ============================================================

  void _showVoiceResultDialog(
    Map result, {
    required String source,
    int? historyId,
  }) {
    final label = result['label']?.toString() ?? 'Unknown';

    var confidence =
        double.tryParse(result['confidence']?.toString() ?? '') ?? 0.0;

    // Accept either 0-100 or 0-1.
    if (confidence <= 1.0) {
      confidence *= 100;
    }

    confidence = confidence.clamp(0.0, 100.0).toDouble();

    final lower = label.toLowerCase();

    final isSynthetic =
        !lower.contains('possible') &&
        !lower.contains('suspicious') &&
        (RegExp(r'\bai\b').hasMatch(lower) ||
            lower.contains('deepfake') ||
            lower.contains('synthetic'));

    final isUnknown =
        !lower.contains('human') &&
        (lower.contains('suspicious') ||
            lower.contains('possible') ||
            !isSynthetic);

    // ==========================================================
    // AUDIO ACTION
    //
    // Human Voice
    //     -> Allowed
    //
    // Suspicious / Possible AI
    //     -> Alert Shown
    //
    // AI / Deepfake
    //     -> Alert Shown
    //
    // This intentionally does NOT use result['action']
    // because the older voice service may still return
    // "Blocked" for AI/deepfake results.
    // ==========================================================

    final action = 'Analysis shown';

    final Color tone = isSynthetic
        ? dangerColor
        : isUnknown
        ? primaryBlue
        : successColor;

    final IconData toneIcon = isSynthetic
        ? Icons.warning_amber_rounded
        : isUnknown
        ? Icons.help_outline_rounded
        : Icons.check_circle_outline_rounded;

    final String verdict = isSynthetic
        ? 'Likely AI-generated voice'
        : isUnknown
        ? 'Unable to determine voice type'
        : 'Likely a human voice';

    final String advice = isSynthetic
        ? "Be careful with this audio. "
              "Do not share codes, passwords, "
              "or send money based only on "
              "this voice."
        : isUnknown
        ? "PARE could not make a clear "
              "determination. Try a longer "
              "or clearer audio sample."
        : "No strong signs of AI-generated "
              "voice were detected. Still "
              "verify unexpected requests "
              "independently.";

    final IconData sourceIcon = source.toLowerCase().contains('record')
        ? Icons.mic_none_rounded
        : Icons.upload_file_outlined;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return _pareDialogShell(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SOURCE CHIP + CLOSE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sourceIcon, size: 14, color: mutedColor),
                        const SizedBox(width: 6),
                        Text(
                          source,
                          style: const TextStyle(
                            fontSize: 12,
                            color: mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(dialogContext),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: mutedColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // VERDICT
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(toneIcon, size: 26, color: tone),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Result',
                          style: TextStyle(fontSize: 12, color: mutedColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          verdict,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: inkColor,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // CONFIDENCE
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Confidence',
                    style: TextStyle(fontSize: 13, color: mutedColor),
                  ),
                  Text(
                    '${confidence.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: confidence / 100,
                  minHeight: 8,
                  backgroundColor: borderColor,
                  valueColor: AlwaysStoppedAnimation<Color>(tone),
                ),
              ),

              const SizedBox(height: 14),

              // ACTION
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Action',
                    style: TextStyle(fontSize: 13, color: mutedColor),
                  ),
                  Flexible(
                    child: Text(
                      action,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: action == 'Allowed' ? successColor : dangerColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ADVICE
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: accentBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        advice,
                        style: const TextStyle(
                          fontSize: 13,
                          color: inkColor,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // HISTORY BUTTON
              if (historyId != null)
                _dialogPrimaryButton('View Detection History', () {
                  Navigator.pop(dialogContext);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(openHistoryId: historyId),
                    ),
                  );
                }),

              if (historyId != null) const SizedBox(height: 4),

              // GOT IT
              _dialogTextButton('Got it', () => Navigator.pop(dialogContext)),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // PROTECTION ACTIVATION
  // ============================================================

  Future<void> _onActivate() async {
    final prefs = await PrivatePreferences.getInstance();

    final newState = !_isActivated;

    if (newState) {
      final granted = await PermissionService()
          .requestAllProtectionPermissions();

      await NotificationService.init();

      if (!granted) {
        if (!mounted) return;

        await _showPAREAlert(
          title: "Allow access to turn on protection",
          message:
              "PARE needs the required "
              "permissions to activate its "
              "protection features. You can "
              "enable them in your device settings.",
          icon: Icons.lock_open_rounded,
          iconColor: primaryBlue,
          buttonText: "Open settings",
          secondaryButtonText: "Not now",
          onButtonPressed: () {
            openAppSettings();
          },
          rows: const [
            _AlertRow(icon: Icons.sms_outlined, label: "Read incoming SMS"),
            _AlertRow(
              icon: Icons.mic_none_rounded,
              label: "Use the microphone",
            ),
            _AlertRow(
              icon: Icons.notifications_none_rounded,
              label: "Send you alerts",
            ),
          ],
        );

        return;
      }

      await prefs.setBool(_prefKey, true);

      await _loadState();
    } else {
      await prefs.setBool(_prefKey, false);

      await _stopSmsListener();
      await _stopCallDetection();

      if (!mounted) return;

      setState(() {
        _isActivated = false;
      });
    }

    if (!mounted) return;

    await _showPAREAlert(
      title: newState ? "Protection is on" : "Protection is off",
      message: newState
          ? "SMS protection can analyze messages in the background. Android battery restrictions may delay checks; force-stop pauses protection until you reopen the app. Alerts require notification permission. Voice checks require the app to be open."
          : "Automatic detection has stopped. "
                "You can turn protection back on "
                "anytime from Home.",
      icon: newState ? Icons.verified_user_rounded : Icons.shield_outlined,
      iconColor: newState ? successColor : mutedColor,
      solidIcon: newState,
      buttonText: "Done",
      rows: newState
          ? [
              _AlertRow(
                icon: Icons.graphic_eq_rounded,
                label: "Audio detection",
                badge: _callDetection ? "On" : "Off",
                badgeOn: _callDetection,
              ),
              _AlertRow(
                icon: Icons.chat_bubble_outline,
                label: "Message detection",
                badge: _msgDetection ? "On" : "Off",
                badgeOn: _msgDetection,
              ),
            ]
          : const [],
    );
  }

  // ============================================================
  // VOICE / AUDIO RECORDING
  // ============================================================

  Future<void> _onTestVoiceDetection() async {
    if (!await _allowVoiceAction()) return;
    if (_isRecordingVoice || _isUploadingVoice) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isRecordingVoice = true;
    });

    try {
      final result = await callDetectionService.runVoiceDemoTest();

      if (!mounted) return;

      setState(() {
        _isRecordingVoice = false;
      });

      if (result == null) {
        await _showPAREAlert(
          title: "Voice Detection Failed",
          message:
              "PARE was unable to analyze "
              "the recorded sample. Please try again.",
          icon: Icons.error_outline,
          iconColor: dangerColor,
        );

        return;
      }

      final historyId = await saveVoiceToHistory(
        result: result,
        source: 'Recorded Sample',
      );

      if (!mounted) return;

      _showVoiceResultDialog(
        result,
        source: "Recorded Sample",
        historyId: historyId,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Voice recording analysis error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isRecordingVoice = false;
      });

      await _showPAREAlert(
        title: "Voice Analysis Failed",
        message:
            "PARE was unable to analyze "
            "the recorded sample. Please try again.",
        icon: Icons.error_outline,
        iconColor: dangerColor,
      );
    }
  }

  Future<bool> _allowVoiceAction() async {
    final prefs = await PrivatePreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('call_detection') ?? true) return true;
    if (mounted) {
      await _showPAREAlert(
        title: 'Voice Detection is off',
        message:
            'Turn on Voice Detection in Settings before recording or uploading audio.',
        icon: Icons.mic_off_outlined,
        iconColor: Colors.orange,
      );
    }
    return false;
  }

  // ============================================================
  // VOICE / AUDIO FILE UPLOAD
  // ============================================================

  Future<void> _onUploadVoiceFile() async {
    if (!await _allowVoiceAction()) return;
    if (_isRecordingVoice || _isUploadingVoice) {
      return;
    }

    try {
      debugPrint('📁 Opening audio file picker...');

      final picked = await FilePicker.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (picked == null || picked.files.isEmpty) {
        debugPrint('📁 No audio file selected.');
        return;
      }

      final selectedFile = picked.files.single;

      if (selectedFile.path == null) {
        debugPrint('❌ Selected file has no accessible path.');

        if (!mounted) return;

        await _showPAREAlert(
          title: "File Unavailable",
          message:
              "The selected audio file could "
              "not be accessed. Please choose "
              "another file.",
          icon: Icons.audio_file_outlined,
          iconColor: dangerColor,
        );

        return;
      }

      final file = File(selectedFile.path!);

      final fileName = selectedFile.name;

      if (!await file.exists()) {
        debugPrint('Selected audio file is unavailable');

        if (!mounted) return;

        await _showPAREAlert(
          title: "File Not Found",
          message:
              "The selected audio file could "
              "not be found. Please choose "
              "another file.",
          icon: Icons.folder_off_outlined,
          iconColor: dangerColor,
        );

        return;
      }

      debugPrint('Audio file selected');
      debugPrint('📦 Size: ${await file.length()} bytes');

      if (!mounted) return;

      setState(() {
        _isUploadingVoice = true;
      });

      try {
        final result = await callDetectionService.analyzeAudioFile(
          file.path,
          fileName: fileName,
        );

        if (!mounted) return;

        setState(() {
          _isUploadingVoice = false;
        });

        debugPrint('🎤 Upload Voice Result: $result');

        if (result == null) {
          await _showPAREAlert(
            title: "Analysis Unavailable",
            message:
                "PARE could not determine "
                "a result for the uploaded audio.",
            icon: Icons.help_outline,
            iconColor: primaryBlue,
          );

          return;
        }

        final historyId = await saveVoiceToHistory(
          result: result,
          source: 'Uploaded Audio',
          fileName: fileName,
        );

        if (!mounted) return;

        _showVoiceResultDialog(
          result,
          source: "Uploaded Audio",
          historyId: historyId,
        );
      } catch (e, stackTrace) {
        debugPrint('❌ Uploaded voice analysis error: $e');
        debugPrint('$stackTrace');

        if (!mounted) return;

        setState(() {
          _isUploadingVoice = false;
        });

        await _showPAREAlert(
          title: "Voice Analysis Failed",
          message:
              "PARE was unable to analyze "
              "the selected audio file. Please "
              "try another file or try again.",
          icon: Icons.error_outline,
          iconColor: dangerColor,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ File picker error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      await _showPAREAlert(
        title: "Unable to Open Audio",
        message:
            "PARE could not open the audio "
            "file picker. Please try again.",
        icon: Icons.folder_off_outlined,
        iconColor: dangerColor,
      );
    }
  }

  // ============================================================
  // ============================================================
  //                        NEW UI (VIEW ONLY)
  // ============================================================
  // ============================================================

  // ─── Header ────────────────────────────────────────────────────────────────
  // Same header on every screen (see pare_shell.dart). The update bell is
  // wired through PareUpdateStatus below.

  Widget _header() {
    return PareHeader(
      title: 'PARE',
      subtitle: 'Hello, $_username',
      username: _username,
    );
  }

  // ─── Shared pieces ─────────────────────────────────────────────────────────

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: dividerColor);

  Widget _iconBadge(IconData icon, {Color? tint}) {
    final color = tint ?? primaryBlue;

    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

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

  /// Icon + title + subtitle row used inside cards.
  Widget _infoRow({
    required IconData icon,
    required String title,
    String? subtitle,
    Color tint = accentBlue,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _iconBadge(icon, tint: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: inkColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: mutedColor,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );

    if (onTap == null) return row;

    return InkWell(onTap: onTap, child: row);
  }

  /// Rows separated by thin dividers, inside one card.
  Widget _rowsCard(List<Widget> rows) {
    final children = <Widget>[];

    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i < rows.length - 1) children.add(_divider());
    }

    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(children: children),
    );
  }

  // ─── Shield hero ───────────────────────────────────────────────────────────

  Widget _pulseRing(double t, bool on) {
    final scale = 0.62 + (1.15 - 0.62) * t;
    final opacity = (0.9 * (1 - t)).clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: on
                  ? const Color(0xFFA0FFD2).withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroChip(String label, bool on) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on
                    ? const Color(0xFF7CF0B8)
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

  Widget _hero() {
    final on = _isActivated;

    final title = on ? 'Protection is active' : 'Protection is off';

    final subtitle = on
        ? (_msgDetection || _callDetection
              ? 'SMS checks run automatically. Open the app for voice checks.'
              : 'Protection is active, but all detection options are turned off.')
        : 'Tap the shield to activate.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: on
              ? const [Color(0xFF0A3A47), Color(0xFF157A5B)]
              : const [primaryBlue, heroBlue],
        ),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.topCenter,
        children: [
          const Positioned(
            right: -80,
            top: -90,
            child: CustomPaint(size: Size(220, 220), painter: RingsPainter()),
          ),

          Column(
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) => Stack(
                        alignment: Alignment.center,
                        children: [
                          _pulseRing(_pulse.value, on),
                          _pulseRing((_pulse.value + 0.5) % 1.0, on),
                        ],
                      ),
                    ),

                    Semantics(
                      button: !on,
                      label: on ? 'Protection active' : 'Activate protection',
                      child: GestureDetector(
                        onTap: on ? null : _onActivate,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: on
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.14),
                            border: Border.all(
                              color: on
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                            boxShadow: on
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 0,
                                      spreadRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            on
                                ? Icons.verified_user_rounded
                                : Icons.shield_outlined,
                            size: 46,
                            color: on ? const Color(0xFF157A5B) : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.80),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),

              if (on) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    _heroChip('Audio', _callDetection),
                    const SizedBox(width: 6),
                    _heroChip('Messages', _msgDetection),
                    const SizedBox(width: 6),
                    _heroChip('Alerts', _smsAlertsActive),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── Voice check tiles ─────────────────────────────────────────────────────

  Widget _voiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool primary,
    required bool busy,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final fg = primary ? Colors.white : primaryBlue;

    return Expanded(
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.5,
        child: Material(
          color: primary ? primaryBlue : softBlue,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 92),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: fg,
                          ),
                        )
                      : Icon(icon, size: 24, color: fg),
                  const SizedBox(height: 12),
                  Text(
                    busy ? 'Analyzing...' : title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceActions() {
    final isBusy = _isRecordingVoice || _isUploadingVoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _voiceTile(
              icon: Icons.mic_rounded,
              title: 'Record sample',
              subtitle: 'Speak or play a call',
              primary: true,
              busy: _isRecordingVoice,
              onTap: isBusy || !_callDetection ? null : _onTestVoiceDetection,
            ),
            const SizedBox(width: 10),
            _voiceTile(
              icon: Icons.upload_file_outlined,
              title: 'Upload file',
              subtitle: 'Pick an audio file',
              primary: false,
              busy: _isUploadingVoice,
              onTap: isBusy || !_callDetection ? null : _onUploadVoiceFile,
            ),
          ],
        ),

        if (!_callDetection) ...[
          const SizedBox(height: 8),
          const Text(
            'Voice Detection is off. Enable it in Settings.',
            style: TextStyle(fontSize: 11.5, color: mutedColor),
          ),
        ],
      ],
    );
  }

  // ─── Recent activity ───────────────────────────────────────────────────────

  Widget _recentRow(Map<String, dynamic> data) {
    final isAudio = (data['category'] ?? '') == 'Audio';
    final risk = historyRiskLabel(data['riskLevel'] as String?);

    final Color tone = risk == 'HIGH'
        ? dangerColor
        : risk == 'MEDIUM'
        ? warningColor
        : risk == 'LOW'
        ? successColor
        : mutedColor;

    final String riskText = risk == 'HIGH'
        ? 'High'
        : risk == 'MEDIUM'
        ? 'Medium'
        : risk == 'LOW'
        ? 'Low'
        : 'Unknown';

    final name = isAudio
        ? (data['name']?.toString() ?? 'Voice check')
        : _recentSender(data['name']);

    final kind = isAudio ? 'Voice check' : 'Text message';
    final when = _recentWhen(data['dateTime']);

    final IconData icon = risk == 'HIGH'
        ? Icons.warning_amber_rounded
        : isAudio
        ? Icons.mic_none_rounded
        : Icons.sms_outlined;

    final id = data['id'];

    return _infoRow(
      icon: icon,
      tint: risk == 'HIGH' ? dangerColor : accentBlue,
      title: name,
      subtitle: when.isEmpty ? kind : '$kind · $when',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          riskText,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: tone,
          ),
        ),
      ),
      onTap: id is int
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(openHistoryId: id),
                ),
              );
            }
          : null,
    );
  }

  Widget _recentActivity() {
    if (_recent.isEmpty) {
      return _card(
        child: const Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: mutedColor),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No activity yet. Detected messages and voice checks will appear here.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: mutedColor,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return _rowsCard(_recent.map(_recentRow).toList());
  }

  // ─── Inactive view ─────────────────────────────────────────────────────────

  Widget _inactiveView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hero(),

        _sectionLabel('When active, PARE will'),

        _rowsCard([
          _infoRow(
            icon: Icons.graphic_eq_rounded,
            title: 'Check voices',
            subtitle: _callDetection
                ? 'Analyze audio for possible AI-generated voices'
                : 'Audio analysis is currently off',
          ),
          _infoRow(
            icon: Icons.sms_outlined,
            title: 'Scan text messages',
            subtitle: _msgDetection
                ? 'Detect scam SMS messages'
                : 'Message detection is currently off',
          ),
          _infoRow(
            icon: Icons.notifications_active_outlined,
            title: 'Warn you',
            subtitle: _msgScamAlerts
                ? 'Show SMS warnings when notifications are allowed'
                : 'Scam message alerts are currently off',
          ),
        ]),

        const Padding(
          padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Center(
            child: Text(
              'You can change these options anytime in Settings.',
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ─── Active view ───────────────────────────────────────────────────────────

  Widget _activeView() {
    final String messageStatus = _smsAlertsActive
        ? 'Scam alerts on'
        : !_msgScamAlerts && _msgDetection
        ? 'Permission needed'
        : 'Scam alerts off';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hero(),

        _sectionLabel('Voice authenticity check'),
        _voiceActions(),

        _sectionLabel('How it responds'),
        _rowsCard([
          // Audio currently shows results in the app rather than blocking.
          _infoRow(
            icon: Icons.graphic_eq_rounded,
            title: 'Audio',
            trailing: _statusPill(
              _callDetection ? 'Results in app' : 'Off',
              _callDetection,
            ),
          ),
          _infoRow(
            icon: Icons.sms_outlined,
            title: 'Messages',
            trailing: _statusPill(messageStatus, _smsAlertsActive),
          ),
        ]),

        _sectionLabel('Recent activity'),
        _recentActivity(),

        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: TextButton(
            onPressed: _onActivate,
            style: TextButton.styleFrom(
              foregroundColor: dangerColor,
              backgroundColor: dangerColor.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Deactivate protection',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    if (PareUpdateStatus.instance.openUpdates == _openUpdatesScreen) {
      PareUpdateStatus.instance.openUpdates = null;
    }

    _pulse.dispose();

    _smsSubscription?.cancel();

    smsModel.close();

    callDetectionService.stop();
    callDetectionService.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryBlue))
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),

                    const SizedBox(height: 16),

                    Expanded(
                      child: SingleChildScrollView(
                        child: _isActivated ? _activeView() : _inactiveView(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ============================================================
// ALERT ROW MODEL
// ============================================================

class _AlertRow {
  final IconData icon;
  final String label;

  final String? badge;

  final bool badgeOn;

  const _AlertRow({
    required this.icon,
    required this.label,
    this.badge,
    this.badgeOn = true,
  });
}
