import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/features/1_auth/screens/splash_screen.dart';
import 'package:pare_app/features/1_auth/screens/onboarding_screen.dart';
import 'package:pare_app/features/1_auth/screens/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  // Advance animation frames until routing completes, with a bounded deadline.
  // pumpAndSettle alone can finish between the splash's typing timer ticks.
  Future<void> waitForRoute(WidgetTester tester, Finder destination) async {
    for (var i = 0; i < 100 && destination.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(destination, findsOneWidget);

    // Allow the navigation fade transition to finish.
    // Do not use pumpAndSettle because the splash has a periodic cursor timer.
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'Startup routes first launch to onboarding and returning users to login after a brief splash',
    (tester) async {
      final prefs = await PrivatePreferences.getInstance();
      await prefs.setBool('onboarding_seen', false);
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      expect(find.byType(SplashScreen), findsOneWidget);
      await waitForRoute(tester, find.byType(OnboardingScreen));
      await tester.pumpWidget(const SizedBox());
      await prefs.setBool('onboarding_seen', true);
      await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
      expect(find.byType(SplashScreen), findsOneWidget);
      await waitForRoute(tester, find.byType(LoginScreen));
      expect(find.byType(OnboardingScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
