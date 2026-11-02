import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/features/3_history/widgets/history_presentation.dart';

void main() {
  test('Missing actions and risks are unknown, not fabricated from scores', () {
    expect(historyActionLabel(null), 'Not recorded');
    expect(historyRiskLabel(null), 'UNKNOWN');
    expect(historyRiskLabel('unexpected'), 'UNKNOWN');
    expect(historyRiskLabel(' medium '), 'MEDIUM');
  });
  test('History does not claim that opening Messages blocks a sender', () {
    expect(
      historyActionLabel('Message Opened for Blocking'),
      'Messages opened',
    );
    expect(historyActionLabel('Blocked'), 'Block not verified');
    expect(historyActionLabel('Allowed'), 'Logged Only');
    expect(historyActionLabel('Alert Shown'), 'Alert Shown');
  });
}
