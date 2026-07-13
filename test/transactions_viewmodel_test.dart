import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/transactions/viewmodels/transactions_viewmodel.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({
  required String id,
  required String userCardId,
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
          _tx(id: '1', userCardId: '', amount: 100),
        ],
      );
      final summary = state.perCardSummary();
      expect(summary.isEmpty, isTrue);
    });
  });
}
