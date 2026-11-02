import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pare_app/core/ml/sms_risk_policy.dart';

void main() {
  final directory = Directory('../sms_model_files/release_v4');
  final manifest = jsonDecode(
    File('${directory.path}/manifest.json').readAsStringSync(),
  );
  final threshold = (manifest['cautionThreshold'] as num).toDouble();
  test('Exported model scores and app rules pass reported regressions', () {
    final cases =
        jsonDecode(
              File(
                '${directory.path}/regression_scores.json',
              ).readAsStringSync(),
            )
            as List;
    for (final row in cases) {
      final result = SmsRiskPolicy.assess(
        row['message'],
        (row['modelScore'] as num).toDouble(),
        cautionThreshold: threshold,
      );
      expect(result.riskLevel, row['expectedRisk'], reason: row['message']);
      expect(result.explanation, isNotEmpty);
    }
  });

  test('Record final hybrid performance on the frozen development corpus', () {
    final rows =
        jsonDecode(File('${directory.path}/held_out.json').readAsStringSync())
            as List;
    final matrix = [
      [0, 0],
      [0, 0],
    ];
    final severityCounts = <String, int>{};
    for (final row in rows) {
      final result = SmsRiskPolicy.assess(
        row['message'],
        (row['modelScore'] as num).toDouble(),
        cautionThreshold: threshold,
      );
      matrix[row['label'] as int][result.riskLevel == 'LOW' ? 0 : 1]++;
      severityCounts.update(result.riskLevel, (n) => n + 1, ifAbsent: () => 1);
    }
    final tn = matrix[0][0],
        fp = matrix[0][1],
        fn = matrix[1][0],
        tp = matrix[1][1];
    final precision = tp / (tp + fp), recall = tp / (tp + fn);
    File('${directory.path}/hybrid_evaluation.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'samples': rows.length,
        'confusionMatrix': matrix,
        'severityCounts': severityCounts,
        'precision': precision,
        'recall': recall,
        'f1': 2 * precision * recall / (precision + recall),
        'accuracy': (tn + tp) / rows.length,
        'interpretation':
            'Medium or High means flagged. Source labels mix spam and scams. Development evaluation, not deployment certification.',
      }),
    );
    expect(tn + fp + fn + tp, rows.length);
  });
}
