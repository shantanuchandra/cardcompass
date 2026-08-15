import 'package:cardcompass/features/insights/domain/spend_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('insight derives spend and unresolved shares', () {
    final insight = SpendInsight(
      kind: SpendInsightKind.category,
      key: const SpendInsightKey(value: 'grocery', label: 'Grocery'),
      periodStart: DateTime(2026, 6, 16),
      periodEnd: DateTime(2026, 8, 15),
      amount: 12000,
      totalEligibleSpend: 30000,
      transactionCount: 8,
      unresolvedAmount: 1500,
    );

    expect(insight.shareOfEligibleSpend, .4);
    expect(insight.unresolvedShare, .05);
  });

  test('zero total produces finite zero shares', () {
    final insight = SpendInsight(
      kind: SpendInsightKind.category,
      key: const SpendInsightKey(value: 'other', label: 'Other'),
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 15),
      amount: 0,
      totalEligibleSpend: 0,
      transactionCount: 0,
    );

    expect(insight.shareOfEligibleSpend, 0);
    expect(insight.unresolvedShare, 0);
  });
}
