import 'package:cardcompass/core/services/retail_transaction_aggregation.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction({
  required String id,
  required DateTime date,
  required double amount,
  TransactionType type = TransactionType.debit,
  String description = 'Retail purchase',
  String? category = 'grocery',
  double? rewardEarned,
  Map<String, dynamic> metadata = const {},
}) {
  return Transaction(
    id: id,
    userId: 'user-1',
    userCardId: 'card-1',
    amount: amount,
    description: description,
    category: category,
    transactionType: type,
    transactionDate: date,
    rewardEarned: rewardEarned,
    metadata: metadata,
    createdAt: date,
  );
}

void main() {
  test('closed bounds retain rows exactly on both endpoints', () {
    final from = DateTime(2026, 8, 1, 9);
    final through = DateTime(2026, 8, 2, 18);

    final aggregate = aggregateRetailTransactions(
      [
        _transaction(
          id: 'before',
          date: from.subtract(const Duration(microseconds: 1)),
          amount: 5,
        ),
        _transaction(id: 'from', date: from, amount: 10),
        _transaction(id: 'through', date: through, amount: 20),
        _transaction(
          id: 'after',
          date: through.add(const Duration(microseconds: 1)),
          amount: 40,
        ),
      ],
      fromInclusive: from,
      throughInclusive: through,
    );

    expect(aggregate.purchases.map((transaction) => transaction.id), [
      'from',
      'through',
    ]);
    expect(aggregate.totalSpend, 30);
  });

  test('spend excludes non-retail types, cash, and invalid amounts', () {
    final date = DateTime(2026, 8, 5);

    final aggregate = aggregateRetailTransactions([
      _transaction(id: 'purchase', date: date, amount: 100),
      _transaction(
        id: 'credit',
        date: date,
        amount: 200,
        type: TransactionType.credit,
      ),
      _transaction(
        id: 'refund',
        date: date,
        amount: 300,
        type: TransactionType.refund,
      ),
      _transaction(
        id: 'fee',
        date: date,
        amount: 400,
        type: TransactionType.fee,
      ),
      _transaction(
        id: 'interest',
        date: date,
        amount: 500,
        type: TransactionType.interest,
      ),
      _transaction(
        id: 'reward',
        date: date,
        amount: 600,
        type: TransactionType.reward,
      ),
      _transaction(
        id: 'cash',
        date: date,
        amount: 700,
        metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
      ),
      _transaction(id: 'zero', date: date, amount: 0),
      _transaction(id: 'negative', date: date, amount: -1),
      _transaction(id: 'nan', date: date, amount: double.nan),
      _transaction(id: 'infinite', date: date, amount: double.infinity),
    ]);

    expect(aggregate.purchases.map((transaction) => transaction.id), [
      'purchase',
    ]);
    expect(aggregate.totalSpend, 100);
  });

  test('natural-key duplicates keep the first eligible row across ids', () {
    final date = DateTime(2026, 8, 5, 12);

    final aggregate = aggregateRetailTransactions([
      _transaction(
        id: 'first-id',
        date: date,
        amount: 100,
        description: 'Same billed purchase',
        rewardEarned: 5,
      ),
      _transaction(
        id: 'second-id',
        date: date,
        amount: 100,
        description: 'Same billed purchase',
        rewardEarned: 50,
      ),
    ]);

    expect(aggregate.purchases.map((transaction) => transaction.id), [
      'first-id',
    ]);
    expect(aggregate.totalSpend, 100);
    expect(aggregate.totalRewards, 5);
  });

  test('rewards are positive finite values on canonical purchases only', () {
    final date = DateTime(2026, 8, 5);

    final aggregate = aggregateRetailTransactions([
      _transaction(id: 'valid', date: date, amount: 100, rewardEarned: 10),
      _transaction(
        id: 'negative',
        date: date.add(const Duration(hours: 1)),
        amount: 50,
        rewardEarned: -5,
      ),
      _transaction(
        id: 'nan',
        date: date.add(const Duration(hours: 2)),
        amount: 25,
        rewardEarned: double.nan,
      ),
      _transaction(
        id: 'credit',
        date: date.add(const Duration(hours: 3)),
        amount: 80,
        type: TransactionType.credit,
        rewardEarned: 80,
      ),
    ]);

    expect(aggregate.totalSpend, 175);
    expect(aggregate.totalRewards, 10);
  });

  test('category and local-day totals use the identical purchase set', () {
    final localMorning = DateTime(2026, 8, 5, 8);

    final aggregate = aggregateRetailTransactions([
      _transaction(
        id: 'grocery',
        date: localMorning,
        amount: 100,
        category: 'grocery',
      ),
      _transaction(
        id: 'uncategorized',
        date: localMorning.add(const Duration(hours: 4)),
        amount: 25,
        category: null,
      ),
      _transaction(
        id: 'travel',
        date: localMorning.add(const Duration(days: 1)),
        amount: 75,
        category: 'travel',
      ),
      _transaction(
        id: 'cash',
        date: localMorning,
        amount: 900,
        category: 'grocery',
        metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
      ),
    ]);

    expect(aggregate.totalSpend, 200);
    expect(aggregate.categoryTotals, {
      'grocery': 100,
      'Other': 25,
      'travel': 75,
    });
    expect(aggregate.localDayTotals, {
      DateTime(2026, 8, 5): 125,
      DateTime(2026, 8, 6): 75,
    });
    expect(
      aggregate.categoryTotals.values.fold<double>(
        0,
        (sum, value) => sum + value,
      ),
      aggregate.totalSpend,
    );
    expect(
      aggregate.localDayTotals.values.fold<double>(
        0,
        (sum, value) => sum + value,
      ),
      aggregate.totalSpend,
    );
  });
}
