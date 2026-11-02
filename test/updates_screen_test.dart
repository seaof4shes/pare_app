import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/features/4_settings/screens/updates_screen.dart';

void main() {
  Widget screen({String latest = '1.0.7'}) => MaterialApp(
    home: UpdatesScreen(
      appUpdateAvailable: latest.isNotEmpty,
      smsModelUpdateAvailable: false,
      voiceModelUpdateAvailable: false,
      installedAppVersion: '1.0.6',
      latestAppVersion: latest,
      installedSmsModelVersion: 4,
      latestSmsModelVersion: 4,
      installedVoiceModelVersion: 4,
      latestVoiceModelVersion: 4,
    ),
  );
  testWidgets('Available update shows current and latest versions directly', (
    tester,
  ) async {
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('1.0.6'), findsOneWidget);
    expect(find.text('1.0.7'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Version v4'), findsNothing);
    expect(find.text('Detection models'), findsNothing);
    expect(find.text('Download APK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Model-only updates do not advertise an app update', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UpdatesScreen(
          appUpdateAvailable: false,
          smsModelUpdateAvailable: true,
          voiceModelUpdateAvailable: true,
          installedAppVersion: '1.0.8',
          latestAppVersion: '1.0.8',
          installedSmsModelVersion: 4,
          latestSmsModelVersion: 5,
          installedVoiceModelVersion: 6,
          latestVoiceModelVersion: 7,
        ),
      ),
    );
    expect(find.text('Everything is up to date'), findsOneWidget);
    expect(find.text('Download APK'), findsNothing);
    expect(find.text('Detection models'), findsNothing);
    expect(find.text('Voice checks'), findsNothing);
  });
  testWidgets('Failed update checks do not claim the app is up to date', (
    tester,
  ) async {
    await tester.pumpWidget(screen(latest: ''));
    expect(find.text('Update status unavailable'), findsOneWidget);
    expect(find.text('Version 1.0.6'), findsOneWidget);
    expect(find.text('Up to Date'), findsNothing);
    expect(find.text('Up to date'), findsNothing);
    expect(find.text('Version v4'), findsNothing);
  });
}
