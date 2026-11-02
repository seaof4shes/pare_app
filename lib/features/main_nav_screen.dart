import '1_auth/screens/login_screen.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pare_app/features/2_home/screens/home_screen.dart';
import 'package:pare_app/features/3_history/screens/history_screen.dart';
import 'package:pare_app/features/4_settings/screens/settings_screen.dart';
import 'package:pare_app/features/widgets/pare_shell.dart';
import 'package:pare_app/services/app_update_service.dart';
import 'package:pare_app/services/notification_service.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  int _selectedIndex = 0;

  int? _openHistoryId;

  StreamSubscription<String>? _notifSub;
  StreamSubscription<dynamic>? _wifiSub;
  DateTime? _lastWifiCheck;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wifiSub = const EventChannel('pare_app/wifi')
        .receiveBroadcastStream()
        .distinct()
        .listen(
          (connected) {
            if (connected != true || !mounted) return;
            final now = DateTime.now();
            if (_lastWifiCheck != null &&
                now.difference(_lastWifiCheck!) < const Duration(seconds: 30)) {
              return;
            }
            _lastWifiCheck = now;
            _homeKey.currentState?.refreshUpdateStatus();
          },
          onError: (_) {
            /* Manual/startup checks remain available. */
          },
        );

    // Listen for notification taps while the app is running.
    _notifSub = NotificationService.onNotificationTap.listen((payload) {
      debugPrint("📲 MainNav received notification payload: $payload");

      _openNotificationHistory(payload);
    });

    // Check if the app was opened by tapping a notification
    // while the app was completely closed.
    final pendingPayload =
        NotificationService.consumePendingNotificationPayload();

    if (pendingPayload != null && pendingPayload.isNotEmpty) {
      debugPrint("🚀 Processing pending notification: $pendingPayload");

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotificationHistory(pendingPayload);
      });
    }

    // Check for application/model updates AFTER the screen loads.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    debugPrint('🔍 Starting PARE update comparison...');

    try {
      final updateService = AppUpdateService();

      final result = await updateService.checkForUpdates();

      if (result['success'] != true) {
        debugPrint('⚠️ Update check was not successful.');
        debugPrint('⚠️ Error: ${result['error']}');
        return;
      }

      debugPrint('✅ Update comparison completed.');

      debugPrint(
        '📱 Installed App: '
        '${result['installedAppVersion']}+'
        '${result['installedAppVersionCode']}',
      );

      debugPrint(
        '☁️ Latest App: '
        '${result['latestAppVersion']}+'
        '${result['latestAppVersionCode']}',
      );

      debugPrint(
        '📩 SMS Model: '
        '${result['installedSmsModelVersion']} → '
        '${result['latestSmsModelVersion']} '
        '(Update: ${result['smsModelUpdateAvailable']})',
      );

      debugPrint(
        '🎤 Voice Model: '
        '${result['installedVoiceModelVersion']} → '
        '${result['latestVoiceModelVersion']} '
        '(Update: ${result['voiceModelUpdateAvailable']})',
      );

      debugPrint(
        '📦 App Update Available: '
        '${result['appUpdateAvailable']}',
      );

      debugPrint(
        '🔔 Any Update Available: '
        '${result['anyUpdateAvailable']}',
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Update check failed: $e');
      debugPrint('❌ Stack trace: $stackTrace');
    }
  }

  void _openNotificationHistory(String payload) {
    final id = int.tryParse(payload);

    if (id == null) {
      debugPrint("⚠️ Invalid notification payload: $payload");
      return;
    }

    debugPrint("🔔 Opening History record with ID: $id");

    if (!mounted) return;

    setState(() {
      // History tab
      _selectedIndex = 1;

      // Tell HistoryScreen which record to open.
      _openHistoryId = id;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _backgroundedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      final last = _backgroundedAt;
      _backgroundedAt = null;
      if (last != null &&
          DateTime.now().difference(last) >= const Duration(minutes: 2) &&
          mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LoginScreen(unlockMode: true),
          ),
          (_) => false,
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifSub?.cancel();
    _wifiSub?.cancel();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;

      // If user manually goes somewhere other than History,
      // clear the selected history record.
      if (index != 1) {
        _openHistoryId = null;
      }
    });

    if (index == 0) {
      _homeKey.currentState?.refreshHomeSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(key: _homeKey),
      HistoryScreen(openHistoryId: _openHistoryId),
      SettingsScreen(
        onSettingsChanged: () {
          _homeKey.currentState?.refreshHomeSettings();
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: PareBottomNav(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
      ),
    );
  }
}
