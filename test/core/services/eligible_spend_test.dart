import 'package:cardcompass/core/services/eligible_spend.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Transaction _transaction(
  TransactionType type, {
  Map<String, dynamic> metadata = const {},
}) {
  return Transaction(
    id: 'transaction-${type.name}',
    userId: 'user-1',
    userCardId: 'card-1',
    amount: 100,
    description: 'Test transaction',
    transactionType: type,
    transactionDate: DateTime(2026, 8, 1),
    metadata: metadata,
    createdAt: DateTime(2026, 8, 1),
  );
}

void main() {
  test('only a retail debit is eligible spend', () {
    expect(isEligibleRetailSpend(_transaction(TransactionType.debit)), isTrue);
    expect(
      isEligibleRetailSpend(_transaction(TransactionType.credit)),
      isFalse,
    );
    expect(
      isEligibleRetailSpend(_transaction(TransactionType.refund)),
      isFalse,
    );
    expect(isEligibleRetailSpend(_transaction(TransactionType.fee)), isFalse);
    expect(
      isEligibleRetailSpend(_transaction(TransactionType.interest)),
      isFalse,
    );
    expect(
      isEligibleRetailSpend(_transaction(TransactionType.reward)),
      isFalse,
    );
  });

  test('legacy cash withdrawal metadata excludes a debit', () {
    expect(
      isEligibleRetailSpend(
        _transaction(
          TransactionType.debit,
          metadata: const {'normalized_transaction_type': 'cash_withdrawal'},
        ),
      ),
      isFalse,
    );
  });
}
