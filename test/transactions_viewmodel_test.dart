import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/transactions/viewmodels/transactions_viewmodel.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({
  required String id,
  required String? userCardId,
  required double amount,
  TransactionType type = TransactionType.debit,
  TransactionCategory category = TransactionCategory.food,
  double? rewardEarned,
  DateTime? date,
}) {
  return Transaction(
    id: id,
    userId: 'u1',
    userCardId: userCardId,
    amount: amount,
    description: 'test',
    category: category,
    type: type,
    transactionDate: date ?? DateTime(2026, 7, 10),
    rewardEarned: rewardEarned,
    createdAt: DateTime(2026, 7, 10),
  );
}

void main() {
  group('TransactionsViewState.perCardSummary', () {
    test('sums spend and rewards per card from filteredTransactions', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, rewardEarned: 5),
          _tx(id: '2', userCardId: 'cardA', amount: 50, rewardEarned: 2),
          _tx(id: '3', userCardId: 'cardB', amount: 200),
          _tx(id: '4', userCardId: 'cardA', amount: 30, type: TransactionType.credit),
        ],
      );

      final summary = state.perCardSummary();

      expect(summary['cardA']!.totalSpend, 150);
      expect(summary['cardA']!.totalRewards, 7);
      expect(summary['cardB']!.totalSpend, 200);
      expect(summary['cardB']!.totalRewards, 0);
      expect(summary.containsKey('cardA'), isTrue);
    });

    test('excludes transactions with null userCardId', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: null, amount: 100),
        ],
      );
      final summary = state.perCardSummary();
      expect(summary.isEmpty, isTrue);
    });

    test('excludes transactions with empty userCardId', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: '', amount: 100),
        ],
      );
      final summary = state.perCardSummary();
      expect(summary.isEmpty, isTrue);
    });
  });

  group('TransactionsViewState.groupedTransactions', () {
    test('flat grouping returns a single group with all filtered transactions, newest first', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, date: DateTime(2026, 7, 1)),
          _tx(id: '2', userCardId: 'cardA', amount: 20, date: DateTime(2026, 7, 10)),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.flat);

      expect(groups.length, 1);
      expect(groups.first.key, 'All Transactions');
      expect(groups.first.transactions.map((t) => t.id).toList(), ['2', '1']);
    });

    test('byCard grouping buckets by userCardId with per-group subtotal', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10),
          _tx(id: '2', userCardId: 'cardB', amount: 20),
          _tx(id: '3', userCardId: 'cardA', amount: 5),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCard);
      final byKey = {for (final g in groups) g.key: g};

      expect(byKey.keys.toSet(), {'cardA', 'cardB'});
      expect(byKey['cardA']!.transactions.length, 2);
      expect(byKey['cardA']!.subtotal, 15);
      expect(byKey['cardB']!.subtotal, 20);
    });

    test('byCard grouping buckets null/empty userCardId under Unknown Card', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: null, amount: 10),
          _tx(id: '2', userCardId: '', amount: 5),
          _tx(id: '3', userCardId: 'cardA', amount: 20),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCard);
      final byKey = {for (final g in groups) g.key: g};

      expect(byKey.containsKey('Unknown Card'), isTrue);
      expect(byKey['Unknown Card']!.transactions.length, 2);
      expect(byKey.containsKey('cardA'), isTrue);
    });

    test('byCategory grouping buckets by category name', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, category: TransactionCategory.food),
          _tx(id: '2', userCardId: 'cardA', amount: 20, category: TransactionCategory.fuel),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byCategory);
      final keys = groups.map((g) => g.key).toSet();

      expect(keys, {'food', 'fuel'});
    });

    test('byDate grouping buckets by year-month', () {
      final state = const TransactionsViewState().copyWith(
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 10, date: DateTime(2026, 6, 15)),
          _tx(id: '2', userCardId: 'cardA', amount: 20, date: DateTime(2026, 7, 1)),
        ],
      );

      final groups = state.groupedTransactions(TransactionGrouping.byDate);
      final keys = groups.map((g) => g.key).toSet();

      expect(keys, {'2026-06', '2026-07'});
    });
  });

  group('TransactionsViewState.spendTrend', () {
    test('buckets by month for All Time and computes daily average, peak day, no prior-period comparison', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: null, // All Time
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 1)),
          _tx(id: '2', userCardId: 'cardA', amount: 50, date: DateTime(2026, 7, 1)),
          _tx(id: '3', userCardId: 'cardA', amount: 300, date: DateTime(2026, 8, 2)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend, isNotNull);
      expect(trend!.bucketing, TrendBucketing.byMonth);
      expect(trend.points.length, 2);
      expect(trend.points[0].total, 150); // Jul: 100+50
      expect(trend.points[1].total, 300); // Aug: 300
      expect(trend.dailyAverage, isPositive);
      expect(trend.peakLabel, isNotNull);
      expect(trend.percentVsPriorPeriod, isNull);
    });

    test('buckets by day within an explicit date range and computes prior-period comparison', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: DateRange(start: DateTime(2026, 7, 8), end: DateTime(2026, 7, 9)),
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
          _tx(id: '2', userCardId: 'cardA', amount: 300, date: DateTime(2026, 7, 9)),
        ],
        transactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
          _tx(id: '2', userCardId: 'cardA', amount: 300, date: DateTime(2026, 7, 9)),
          // prior period (2026-07-06 to 2026-07-07) — total 200
          _tx(id: '3', userCardId: 'cardA', amount: 200, date: DateTime(2026, 7, 6)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend, isNotNull);
      expect(trend!.bucketing, TrendBucketing.byDay);
      expect(trend.points.length, 2);
      expect(trend.points[0].total, 100);
      expect(trend.points[1].total, 300);
      expect(trend.dailyAverage, closeTo(200, 0.01));
      // (400 - 200) / 200 * 100 = 100% increase
      expect(trend.percentVsPriorPeriod, closeTo(100, 0.01));
      expect(trend.peakLabel, isNotNull);
    });

    test('returns null when there are fewer than 2 distinct buckets of data', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: DateRange(start: DateTime(2026, 7, 8), end: DateTime(2026, 7, 8)),
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
        ],
      );

      final trend = state.spendTrend();

      expect(trend, isNull);
    });

    test('returns null when there is no filtered data at all', () {
      final state = const TransactionsViewState().copyWith(filteredTransactions: []);

      final trend = state.spendTrend();

      expect(trend, isNull);
    });

    test('excludes non-debit transactions from bucket totals', () {
      final state = const TransactionsViewState().copyWith(
        dateRange: DateRange(start: DateTime(2026, 7, 8), end: DateTime(2026, 7, 9)),
        filteredTransactions: [
          _tx(id: '1', userCardId: 'cardA', amount: 100, date: DateTime(2026, 7, 8)),
          _tx(id: '2', userCardId: 'cardA', amount: 500, type: TransactionType.credit, date: DateTime(2026, 7, 9)),
        ],
      );

      final trend = state.spendTrend();

      // should return null because only 1 bucket has non-zero debit (Jul 8 has 100, Jul 9 has 0 credit)
      // OR if it returns non-null, the credit tx must not inflate the Jul 9 bucket
      if (trend != null) {
        expect(trend.points.firstWhere((p) => p.bucketStart.day == 9).total, 0);
      }
    });
  });
}
