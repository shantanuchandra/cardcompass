abstract final class TransactionTypeNormalizer {
  static const canonical = {
    'debit',
    'credit',
    'refund',
    'fee',
    'interest',
    'reward',
    'cash_withdrawal',
  };

  static String normalize({String? parserType, required String description}) {
    final raw = parserType?.trim().toLowerCase().replaceAll(' ', '_');
    final text = description.toLowerCase();
    if (RegExp(r'\b(refund|reversal|reversed)\b').hasMatch(text)) {
      return 'refund';
    }
    if (RegExp(r'\b(interest|finance charge)\b').hasMatch(text)) {
      return 'interest';
    }
    if (RegExp(
      r'\b(annual fee|late fee|processing fee|fee charged)\b',
    ).hasMatch(text)) {
      return 'fee';
    }
    if (RegExp(r'\b(atm|cash withdrawal)\b').hasMatch(text)) {
      return 'cash_withdrawal';
    }
    if (RegExp(r'\b(reward|cashback credit|points credit)\b').hasMatch(text)) {
      return 'reward';
    }
    return raw != null && canonical.contains(raw) ? raw : 'debit';
  }
}
