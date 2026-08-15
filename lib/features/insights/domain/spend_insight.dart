enum SpendInsightKind {
  category,
  merchant,
  movie,
  travel,
  ecommerce,
  foodGrocery,
  fuel,
}

class SpendInsightKey {
  const SpendInsightKey({
    required this.value,
    required this.label,
    this.subtype,
  });

  final String value;
  final String label;
  final String? subtype;
}

class SpendInsight {
  const SpendInsight({
    required this.kind,
    required this.key,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.totalEligibleSpend,
    required this.transactionCount,
    this.unresolvedAmount = 0,
  });

  final SpendInsightKind kind;
  final SpendInsightKey key;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double amount;
  final double totalEligibleSpend;
  final int transactionCount;
  final double unresolvedAmount;

  double get shareOfEligibleSpend =>
      totalEligibleSpend == 0 ? 0 : amount / totalEligibleSpend;

  double get unresolvedShare =>
      totalEligibleSpend == 0 ? 0 : unresolvedAmount / totalEligibleSpend;
}
