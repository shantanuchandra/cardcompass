import 'package:cardcompass/core/services/transaction_type_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('description corrects an underspecified debit', () {
    expect(
      TransactionTypeNormalizer.normalize(
        parserType: 'debit',
        description: 'FINANCE CHARGES / INTEREST',
      ),
      'interest',
    );
    expect(
      TransactionTypeNormalizer.normalize(
        parserType: 'debit',
        description: 'ATM CASH WITHDRAWAL',
      ),
      'cash_withdrawal',
    );
  });

  test('canonical parser types pass through', () {
    for (final type in const [
      'debit',
      'credit',
      'refund',
      'fee',
      'interest',
      'reward',
      'cash_withdrawal',
    ]) {
      expect(
        TransactionTypeNormalizer.normalize(parserType: type, description: ''),
        type,
      );
    }
  });

  test('unknown parser values safely fall back to debit', () {
    expect(
      TransactionTypeNormalizer.normalize(
        parserType: 'purchase',
        description: 'LOCAL SHOP',
      ),
      'debit',
    );
  });
}
