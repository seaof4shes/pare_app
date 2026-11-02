import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/features/3_history/widgets/history_detail_sheet.dart';

void main() {
  final message = List.filled(
    10,
    'Thank you for visiting. Please share feedback about your service experience.',
  ).join(' ');
  Map<String, dynamic> record(String risk) => {
    'name': '+63 947 643 0775',
    'senderNumber': '+639476430775',
    'category': 'Messages',
    'type': 'SMS Message',
    'date': '10/30/2026 - 2:49 AM',
    'riskLevel': risk,
    'message': message,
    'safe': risk == 'LOW',
    'detectionExplanation': 'No strong suspicious request was detected.',
    'modelScore': .2755,
    'modelVersion': 4,
    'keywordScore': 0,
    'result': 'Low risk',
  };
  Future<void> open(
    WidgetTester tester,
    Map<String, dynamic> item, {
    VoidCallback? onBlock,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => HistoryDetailSheet.show(
                context,
                item: item,
                actionBadge: const Text('Allowed'),
                onBlock: onBlock ?? () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Low-risk details expand, collapse and copy the original SMS', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = call.arguments['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(tester, record('LOW'));
    expect(find.text('Looks okay'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Message')).dy,
      lessThan(tester.getTopLeft(find.text('Why this result?')).dy),
    );
    final actionLabel = tester.getRect(find.text('What P.A.R.E. did?'));
    final actionValue = tester.getRect(find.text('Allowed'));
    expect(actionValue.left, greaterThan(actionLabel.right));
    expect((actionValue.center.dy - actionLabel.center.dy).abs(), lessThan(2));
    expect(find.text('Open Messages to block'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Show full message'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show full message'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text(message)).maxLines, isNull);
    await tester.ensureVisible(find.text('Copy'));
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, message);
    await tester.scrollUntilVisible(
      find.text('Technical details'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Technical details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('SMS model v4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('High-risk sender action is pinned and closes details first', (
    tester,
  ) async {
    var invoked = false;
    await open(tester, record('HIGH'), onBlock: () => invoked = true);
    expect(find.text('Likely a scam'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('What you can do'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('What you can do'), findsOneWidget);
    await tester.tap(find.text('Open Messages to block'));
    await tester.pumpAndSettle();
    expect(invoked, isTrue);
    expect(find.text('Likely a scam'), findsNothing);
  });

  testWidgets('Medium, legacy and large-text layouts remain usable', (
    tester,
  ) async {
    final item = record('MEDIUM')..remove('detectionExplanation');
    await open(tester, item, scale: 1.6);
    expect(find.text('Be careful'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('older record'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('older record'), findsOneWidget);
    expect(find.text('Open Messages to block'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Human voice score is not described as synthetic confidence', (
    tester,
  ) async {
    final item = record('HIGH')
      ..addAll({
        'category': 'Audio',
        'safe': true,
        'confidenceRaw': 99.0,
        'confidence': '99%',
        'result': 'Human Voice',
      });
    await open(tester, item);
    expect(find.text('Looks okay'), findsOneWidget);
    expect(find.text('Voice classification score'), findsOneWidget);
    expect(find.text('Open Messages to block'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
