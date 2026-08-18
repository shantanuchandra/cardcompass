import 'package:cardcompass/core/services/retail_transaction_aggregation.dart';
import 'package:cardcompass/features/dashboard/domain/dashboard_metrics.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

UserCard _card({
  required String id,
  double? creditLimit,
  bool isActive = true,
}) {
  return UserCard(
    id: id,
    userId: 'user-1',
    catalogCardId: 'catalog-$id',
    creditLimit: creditLimit,
    isActive: isActive,
    createdAt: DateTime(2026, 7, 1),
  );
}

Transaction _transaction({
  required String id,
  required DateTime date,
  required double amount,
  TransactionType type = TransactionType.debit,
  String description = 'Retail purchase',
  double? rewardEarned,
  Map<String, dynamic> metadata = const {},
}) {
  return Transaction(
    id: id,
    userId: 'user-1',
    userCardId: 'card-1',
    amount: amount,
    description: description,
    transactionType: type,
    transactionDate: date,
    rewardEarned: rewardEarned,
    metadata: metadata,
    createdAt: date,
  );
}

void main() {
  final trendStart = DateTime(2026, 7, 1);
  final periodEnd = DateTime(2026, 8, 17, 12);

  test('reported limits include each active positive finite card once', () {
    final metrics = calculateDashboardMetrics(
      cards: [
        _card(id: 'card-1', creditLimit: 100000),
        _card(id: 'card-1', creditLimit: 100000),
        _card(id: 'card-2'),
        _card(id: 'card-3', creditLimit: 200000, isActive: false),
        _card(id: 'card-4', creditLimit: -5000),
        _card(id: 'card-5', creditLimit: double.nan),
      ],
      transactions: const [],
      trendStart: trendStart,
      periodEnd: periodEnd,
      monthCount: 2,
    );

    expect(metrics.totalReportedCardLimits, 100000);
  });

  test('spend includes unique eligible retail debits only', () {
    final purchaseDate = DateTime(2026, 8, 5);
    final metrics = calculateDashboardMetrics(
      cards: const [],
      transactions: [
        _transaction(id: 'purchase', date: purchaseDate, amount: 1000),
        _transaction(id: 'duplicate-row', date: purchaseDate, amount: 1000),
        _transaction(
          id: 'cash',
          date: DateTime(2026, 8, 6),
          amount: 500,
          metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
        ),
        _transaction(
          id: 'refund',
          date: DateTime(2026, 8, 7),
          amount: 300,
          type: TransactionType.refund,
        ),
        _transaction(
          id: 'credit',
          date: DateTime(2026, 8, 8),
          amount: 700,
          type: TransactionType.credit,
        ),
        _transaction(
          id: 'fee',
          date: DateTime(2026, 8, 9),
          amount: 50,
          type: TransactionType.fee,
        ),
        _transaction(id: 'zero', date: DateTime(2026, 8, 10), amount: 0),
        _transaction(
          id: 'invalid',
          date: DateTime(2026, 8, 11),
          amount: double.infinity,
        ),
      ],
      trendStart: trendStart,
      periodEnd: periodEnd,
      monthCount: 2,
    );

    expect(metrics.monthlySpendTrend, [0, 1000]);
  });

  test('rewards include finite values from unique eligible purchases only', () {
    final purchaseDate = DateTime(2026, 8, 5);
    final metrics = calculateDashboardMetrics(
      cards: const [],
      transactions: [
        _transaction(
          id: 'purchase',
          date: purchaseDate,
          amount: 1000,
          rewardEarned: 25,
        ),
        _transaction(
          id: 'duplicate-row',
          date: purchaseDate,
          amount: 1000,
          rewardEarned: 25,
        ),
        _transaction(
          id: 'null-reward',
          date: DateTime(2026, 8, 6),
          amount: 200,
        ),
        _transaction(
          id: 'refund',
          date: DateTime(2026, 8, 7),
          amount: 300,
          type: TransactionType.refund,
          rewardEarned: 10,
        ),
        _transaction(
          id: 'credit',
          date: DateTime(2026, 8, 8),
          amount: 700,
          type: TransactionType.credit,
          rewardEarned: 15,
        ),
        _transaction(
          id: 'invalid-reward',
          date: DateTime(2026, 8, 9),
          amount: 100,
          rewardEarned: double.nan,
        ),
      ],
      trendStart: trendStart,
      periodEnd: periodEnd,
      monthCount: 2,
    );

    expect(metrics.monthlyRewardsTrend, [0, 25]);
  });

  test('month buckets exclude dates outside the closed reporting period', () {
    final metrics = calculateDashboardMetrics(
      cards: const [],
      transactions: [
        _transaction(
          id: 'before',
          date: DateTime(2026, 6, 30, 23, 59),
          amount: 100,
        ),
        _transaction(
          id: 'july',
          date: DateTime(2026, 7, 31, 23, 59),
          amount: 400,
          rewardEarned: 4,
        ),
        _transaction(
          id: 'august',
          date: periodEnd,
          amount: 600,
          rewardEarned: 6,
        ),
        _transaction(
          id: 'future',
          date: periodEnd.add(const Duration(microseconds: 1)),
          amount: 800,
          rewardEarned: 8,
        ),
      ],
      trendStart: trendStart,
      periodEnd: periodEnd,
      monthCount: 2,
    );

    expect(metrics.monthlySpendTrend, [400, 600]);
    expect(metrics.monthlyRewardsTrend, [4, 6]);
  });

  test('dashboard buckets reconcile to the shared canonical aggregate', () {
    final purchaseDate = DateTime(2026, 8, 5);
    final transactions = [
      _transaction(
        id: 'purchase',
        date: purchaseDate,
        amount: 1000,
        description: 'Same billed purchase',
        rewardEarned: 25,
      ),
      _transaction(
        id: 'duplicate-id',
        date: purchaseDate,
        amount: 1000,
        description: 'Same billed purchase',
        rewardEarned: 75,
      ),
      _transaction(
        id: 'cash',
        date: DateTime(2026, 8, 6),
        amount: 500,
        rewardEarned: 50,
        metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
      ),
      _transaction(
        id: 'refund',
        date: DateTime(2026, 8, 7),
        amount: 300,
        type: TransactionType.refund,
        rewardEarned: 30,
      ),
      _transaction(
        id: 'negative-reward',
        date: DateTime(2026, 7, 5),
        amount: 400,
        rewardEarned: -4,
      ),
    ];
    final aggregate = aggregateRetailTransactions(
      transactions,
      fromInclusive: trendStart,
      throughInclusive: periodEnd,
    );

    final metrics = calculateDashboardMetrics(
      cards: const [],
      transactions: transactions,
      trendStart: trendStart,
      periodEnd: periodEnd,
      monthCount: 2,
    );

    expect(
      metrics.monthlySpendTrend.fold<double>(0, (sum, value) => sum + value),
      aggregate.totalSpend,
    );
    expect(
      metrics.monthlyRewardsTrend.fold<double>(0, (sum, value) => sum + value),
      aggregate.totalRewards,
    );
  });
}
