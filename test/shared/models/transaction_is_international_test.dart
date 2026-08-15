import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/shared/models/transaction.dart';

Transaction _tx({required String currency}) {
  return Transaction(
    id: 't1',
    userId: 'u1',
    userCardId: 'c1',
    amount: 100,
    currency: currency,
    description: 'test',
    transactionType: TransactionType.debit,
    transactionDate: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('Transaction.isInternational', () {
    test('false when currency matches the bank market currency', () {
      final tx = _tx(currency: 'INR');
      expect(tx.isInternational('INR'), isFalse);
    });

    test('true when currency differs from the bank market currency', () {
      final tx = _tx(currency: 'USD');
      expect(tx.isInternational('INR'), isTrue);
    });

    test('true for a foreign-currency charge on a UAE-market card', () {
      final tx = _tx(currency: 'EUR');
      expect(tx.isInternational('AED'), isTrue);
    });
  });
}
