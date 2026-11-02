import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pare_app/core/security/private_preferences.dart';
import 'package:pare_app/features/4_settings/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({
    'call_detection': false,
    'msg_detection': true,
  });
  testWidgets(
    'Voice toggle loads, persists and notifies Home without changing SMS',
    (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(onSettingsChanged: () => changes++)),
      );
      await tester.pumpAndSettle();
      final voiceToggle = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Voice detection',
      );
      expect(voiceToggle, findsOneWidget);
      expect(tester.widget<Semantics>(voiceToggle).properties.toggled, isFalse);
      await tester.ensureVisible(voiceToggle);
      await tester.tap(voiceToggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(voiceToggle).properties.toggled, isTrue);
      final prefs = await PrivatePreferences.getInstance();
      expect(prefs.getBool('call_detection'), isTrue);
      expect(prefs.getBool('msg_detection'), isTrue);
      expect(changes, 1);
      await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen(key: ValueKey('reopened'))),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(voiceToggle).properties.toggled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
