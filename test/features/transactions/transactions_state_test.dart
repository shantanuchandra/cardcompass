import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction({
  required String id,
  required TransactionType type,
  required double amount,
  String category = 'food',
  Map<String, dynamic> metadata = const {},
  String userCardId = 'card-1',
  String currency = 'INR',
}) {
  return Transaction(
    id: id,
    userId: 'user-1',
    userCardId: userCardId,
    amount: amount,
    currency: currency,
    description: id,
    category: category,
    transactionType: type,
    transactionDate: DateTime(2026, 8, 1),
    metadata: metadata,
    createdAt: DateTime(2026, 8, 1),
  );
}

UserCard _userCard({required String id, String? bank}) {
  return UserCard(
    id: id,
    userId: 'user-1',
    catalogCardId: 'catalog-1',
    createdAt: DateTime(2026, 8, 1),
    bank: bank,
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

  test('isTransactionInternational is false when the card is not found', () {
    final txn = _transaction(
      id: 'txn-1',
      type: TransactionType.debit,
      amount: 100,
      userCardId: 'card-missing',
      currency: 'USD',
    );
    final state = TxnsState(all: [txn], cards: const []);

    expect(state.isTransactionInternational(txn), isFalse);
  });

  test('isTransactionInternational is false when the card has no bank', () {
    final txn = _transaction(
      id: 'txn-2',
      type: TransactionType.debit,
      amount: 100,
      userCardId: 'card-1',
      currency: 'USD',
    );
    final state = TxnsState(
      all: [txn],
      cards: [_userCard(id: 'card-1', bank: null)],
    );

    expect(state.isTransactionInternational(txn), isFalse);
  });

  test(
    'isTransactionInternational is false for a bank currencyForBank does not recognize',
    () {
      final txn = _transaction(
        id: 'txn-3',
        type: TransactionType.debit,
        amount: 100,
        userCardId: 'card-1',
        currency: 'USD',
      );
      final state = TxnsState(
        all: [txn],
        cards: [
          _userCard(id: 'card-1', bank: 'Some Random Bank Nobody Recognizes'),
        ],
      );

      expect(state.isTransactionInternational(txn), isFalse);
    },
  );

  test(
    'isTransactionInternational is true for a recognized bank with a differing currency',
    () {
      final txn = _transaction(
        id: 'txn-4',
        type: TransactionType.debit,
        amount: 100,
        userCardId: 'card-1',
        currency: 'USD',
      );
      final state = TxnsState(
        all: [txn],
        cards: [_userCard(id: 'card-1', bank: 'HDFC')],
      );

      expect(state.isTransactionInternational(txn), isTrue);
    },
  );
}
