import 'package:cardcompass/core/services/spend_insight_aggregator.dart';
import 'package:cardcompass/features/insights/domain/spend_insight.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction({
  required String id,
  required String merchant,
  required String category,
  required double amount,
  TransactionType type = TransactionType.debit,
  Map<String, dynamic> metadata = const {},
}) {
  return Transaction(
    id: id,
    userId: 'user-1',
    userCardId: 'card-1',
    amount: amount,
    description: merchant,
    merchantName: merchant,
    category: category,
    transactionType: type,
    transactionDate: DateTime(2026, 8, 1),
    metadata: metadata,
    createdAt: DateTime(2026, 8, 1),
  );
}

void main() {
  final start = DateTime(2026, 6, 16);
  final end = DateTime(2026, 8, 15);

  test('builds every insight family and excludes fees', () {
    final transactions = [
      _transaction(
        id: 'food',
        merchant: 'Swiggy',
        category: 'food',
        amount: 900,
        metadata: const {'channel': 'online'},
      ),
      _transaction(
        id: 'grocery',
        merchant: 'BigBasket',
        category: 'grocery',
        amount: 1100,
        metadata: const {'channel': 'online'},
      ),
      _transaction(
        id: 'shopping',
        merchant: 'Amazon',
        category: 'shopping',
        amount: 2100,
        metadata: const {'channel': 'online'},
      ),
      _transaction(
        id: 'travel',
        merchant: 'IndiGo',
        category: 'travel',
        amount: 5000,
      ),
      _transaction(
        id: 'fuel',
        merchant: 'IndianOil',
        category: 'fuel',
        amount: 1800,
      ),
      _transaction(
        id: 'movie',
        merchant: 'BookMyShow',
        category: 'entertainment',
        amount: 1200,
        metadata: const {
          'channel': 'online',
          'platform': 'BookMyShow',
          'merchant_subtype': 'movie_platform',
        },
      ),
      _transaction(
        id: 'fee',
        merchant: 'Annual Fee',
        category: 'other',
        amount: 10000,
        type: TransactionType.fee,
      ),
    ];

    final insights = buildSpendInsights(
      transactions: transactions,
      periodStart: start,
      periodEnd: end,
    );

    expect(
      insights.map((insight) => insight.kind).toSet(),
      containsAll(SpendInsightKind.values),
    );
    expect(
      insights.singleWhere((i) => i.kind == SpendInsightKind.fuel).key.value,
      'indianoil',
    );
    expect(
      insights.every((insight) => insight.totalEligibleSpend == 12100),
      isTrue,
    );
  });

  test('empty input returns no insights', () {
    expect(
      buildSpendInsights(
        transactions: const [],
        periodStart: start,
        periodEnd: end,
      ),
      isEmpty,
    );
  });

  test('ties use count then normalized key alphabetically', () {
    final insights = buildSpendInsights(
      transactions: [
        _transaction(
          id: 'z-1',
          merchant: 'Zulu Cafe',
          category: 'food',
          amount: 500,
        ),
        _transaction(
          id: 'a-1',
          merchant: 'Alpha Cafe',
          category: 'food',
          amount: 500,
        ),
      ],
      periodStart: start,
      periodEnd: end,
    );

    expect(
      insights
          .singleWhere((i) => i.kind == SpendInsightKind.merchant)
          .key
          .value,
      'alpha cafe',
    );
  });
}
