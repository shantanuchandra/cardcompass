import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction({
  required String id,
  required TransactionType type,
  required double amount,
  String category = 'food',
  Map<String, dynamic> metadata = const {},
}) {
  return Transaction(
    id: id,
    userId: 'user-1',
    userCardId: 'card-1',
    amount: amount,
    description: id,
    category: category,
    transactionType: type,
    transactionDate: DateTime(2026, 8, 1),
    metadata: metadata,
    createdAt: DateTime(2026, 8, 1),
  );
}

void main() {
  test('totals and top category include eligible retail spend only', () {
    final state = TxnsState(
      all: [
        _transaction(
          id: 'purchase',
          type: TransactionType.debit,
          amount: 500,
          category: 'grocery',
        ),
        _transaction(id: 'fee', type: TransactionType.fee, amount: 100),
        _transaction(id: 'refund', type: TransactionType.refund, amount: 200),
        _transaction(
          id: 'withdrawal',
          type: TransactionType.debit,
          amount: 1000,
          metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
        ),
      ],
    );

    expect(state.totalSpend, 500);
    expect(state.topCategory, 'grocery');
    expect(state.spendTrend.points.single.total, 500);
  });
}
