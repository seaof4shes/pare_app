import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'features/1_auth/screens/login_screen.dart';
import 'features/main_nav_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('phone');

  runApp(PAREApp(isLoggedIn: phone != null));
}

class PAREApp extends StatelessWidget {
  final bool isLoggedIn;

  const PAREApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: isLoggedIn ? const MainNavScreen() : const LoginScreen(),
    );
  }
}
