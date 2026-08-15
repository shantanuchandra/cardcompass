import '../../shared/models/transaction.dart';

bool isEligibleRetailSpend(Transaction transaction) {
  if (!transaction.isDebit) return false;
  return transaction.metadata['normalized_transaction_type'] !=
      'cash_withdrawal';
}
