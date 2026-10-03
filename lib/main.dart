import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'features/1_auth/screens/login_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize local notifications.
  await NotificationService.init();

  // Always show the Login screen when the app starts.
  //
  // The Login screen determines whether:
  // 1. The account already exists locally → MPIN only
  // 2. The account is not stored locally → Firebase OTP
  runApp(const PAREApp());
}

class PAREApp extends StatelessWidget {
  const PAREApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}