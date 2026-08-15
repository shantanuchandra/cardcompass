import 'package:cardcompass/features/insights/providers/spend_insights_provider.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial period covers the past 60 days', () {
    final now = DateTime(2026, 8, 15, 12);

    final period = InsightPeriod.initial(now);

    expect(period.end, now);
    expect(period.start, now.subtract(const Duration(days: 60)));
  });

  test('provider requests and aggregates the selected period', () async {
    final now = DateTime(2026, 8, 15, 12);
    final reader = _FakeTransactionReader([
      _transaction(
        date: DateTime(2026, 8, 1),
        amount: 900,
        merchant: 'BookMyShow',
        category: 'Entertainment',
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        spendInsightsClockProvider.overrideWithValue(() => now),
        spendInsightsUserIdProvider.overrideWithValue('user-1'),
        spendInsightsTransactionReaderProvider.overrideWithValue(reader),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(spendInsightsProvider.future);

    expect(reader.lastUserId, 'user-1');
    expect(reader.lastFrom, now.subtract(const Duration(days: 60)));
    expect(reader.lastTo, now);
    expect(reader.lastLimit, 2000);
    expect(initial, isNotEmpty);

    final selected = InsightPeriod(DateTime(2026, 8, 1), DateTime(2026, 8, 10));
    await container.read(spendInsightsProvider.notifier).setPeriod(selected);

    expect(reader.lastFrom, selected.start);
    expect(reader.lastTo, selected.end);
    expect(container.read(spendInsightsProvider.notifier).period, selected);
  });
}

class _FakeTransactionReader implements SpendInsightsTransactionReader {
  _FakeTransactionReader(this.transactions);

  final List<Transaction> transactions;
  String? lastUserId;
  DateTime? lastFrom;
  DateTime? lastTo;
  int? lastLimit;

  @override
  Future<List<Transaction>> getTransactions({
    required String userId,
    required DateTime from,
    required DateTime to,
    required int limit,
  }) async {
    lastUserId = userId;
    lastFrom = from;
    lastTo = to;
    lastLimit = limit;
    return transactions;
  }
}

Transaction _transaction({
  required DateTime date,
  required double amount,
  required String merchant,
  required String category,
}) {
  return Transaction(
    id: 'txn-$merchant',
    userId: 'user-1',
    userCardId: 'card-1',
    amount: amount,
    currency: 'INR',
    description: merchant,
    merchantName: merchant,
    category: category,
    transactionDate: date,
    transactionType: TransactionType.debit,
    createdAt: date,
  );
}
