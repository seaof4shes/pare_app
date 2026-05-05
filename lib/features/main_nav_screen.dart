import 'dart:async';

import 'package:flutter/material.dart';

import 'package:pare_app/features/2_home/screens/home_screen.dart';
import 'package:pare_app/features/3_history/screens/history_screen.dart';
import 'package:pare_app/features/4_settings/screens/settings_screen.dart';
import 'package:pare_app/services/notification_service.dart';

class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _selectedIndex = 0;
  int? _openHistoryId;
  StreamSubscription? _notifSub;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  static const Color primaryBlue = Color(0xFF092C56);

  @override
  void initState() {
    super.initState();

    _notifSub = NotificationService.onNotificationTap.listen((payload) {
      final id = int.tryParse(payload);

      if (id != null) {
        setState(() {
          _selectedIndex = 1;
          _openHistoryId = id;
        });
      }
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
      if (index != 1) _openHistoryId = null;
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
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        backgroundColor: Colors.white,
        selectedItemColor: primaryBlue,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: "History",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}
