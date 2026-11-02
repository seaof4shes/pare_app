import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/security/private_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'services/background_sms_worker.dart';
import 'features/1_auth/screens/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> smsBackgroundMain() => runBackgroundSms();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  try {
    final privatePrefs = await PrivatePreferences.getInstance();

    // Initialize Firebase.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Profiles use the encrypted local store for offline access. Do not keep
    // a second unencrypted Firestore disk cache of those same identifiers.
    if (privatePrefs.getBool('firestore_cache_protected_v1') != true) {
      await FirebaseFirestore.instance.clearPersistence();
      await privatePrefs.setBool('firestore_cache_protected_v1', true);
    }
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    // Initialize local notifications.
    await NotificationService.init();

    // Always show the Login screen when the app starts.
    //
    // The Login screen determines whether:
    // 1. The account already exists locally → MPIN only
    // 2. The account is not stored locally → Firebase OTP
    runApp(const PAREApp());
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 16),
                    const Text(
                      'PARE could not open protected data. Your records have not been deleted. Close and reopen the app to retry.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PAREApp extends StatelessWidget {
  const PAREApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PARE',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF092C56)),
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
