import '../../features/insights/domain/spend_insight.dart';
import '../../shared/models/transaction.dart';
import 'eligible_spend.dart';

List<SpendInsight> buildSpendInsights({
  required List<Transaction> transactions,
  required DateTime periodStart,
  required DateTime periodEnd,
}) {
  final eligible = transactions.where((transaction) {
    return isEligibleRetailSpend(transaction) &&
        !transaction.transactionDate.isBefore(periodStart) &&
        !transaction.transactionDate.isAfter(periodEnd);
  }).toList();
  if (eligible.isEmpty) return const [];

  final total = eligible.fold<double>(0, (sum, item) => sum + item.amount);
  final unresolved = eligible
      .where(
        (item) =>
            item.category == null ||
            item.category == 'other' ||
            _merchantValue(item).isEmpty,
      )
      .fold<double>(0, (sum, item) => sum + item.amount);
  final results = <SpendInsight>[];

  void addLeading({
    required SpendInsightKind kind,
    required Iterable<Transaction> source,
    required String Function(Transaction) keyOf,
    required String Function(Transaction) labelOf,
    String? subtype,
  }) {
    final leading = _leadingGroup(source, keyOf: keyOf, labelOf: labelOf);
    if (leading == null) return;
    results.add(
      SpendInsight(
        kind: kind,
        key: SpendInsightKey(
          value: leading.key,
          label: leading.label,
          subtype: subtype,
        ),
        periodStart: periodStart,
        periodEnd: periodEnd,
        amount: leading.amount,
        totalEligibleSpend: total,
        transactionCount: leading.count,
        unresolvedAmount: unresolved,
      ),
    );
  }

  addLeading(
    kind: SpendInsightKind.category,
    source: eligible,
    keyOf: (item) => item.category ?? 'other',
    labelOf: (item) => _title(item.category ?? 'other'),
  );
  addLeading(
    kind: SpendInsightKind.merchant,
    source: eligible.where((item) => _merchantValue(item).isNotEmpty),
    keyOf: _merchantValue,
    labelOf: _merchantLabel,
  );
  addLeading(
    kind: SpendInsightKind.movie,
    source: eligible.where(_isMovie),
    keyOf: _merchantValue,
    labelOf: _merchantLabel,
    subtype: 'movie_platform',
  );
  addLeading(
    kind: SpendInsightKind.travel,
    source: eligible.where((item) => item.category == 'travel'),
    keyOf: _merchantValue,
    labelOf: _merchantLabel,
    subtype: 'travel_merchant',
  );
  addLeading(
    kind: SpendInsightKind.ecommerce,
    source: eligible.where((item) => item.metadata['channel'] == 'online'),
    keyOf: _merchantValue,
    labelOf: _merchantLabel,
    subtype: 'online_merchant',
  );
  addLeading(
    kind: SpendInsightKind.foodGrocery,
    source: eligible.where(
      (item) => item.category == 'food' || item.category == 'grocery',
    ),
    keyOf: _merchantValue,
    labelOf: _merchantLabel,
    subtype: 'food_grocery_merchant',
  );
  addLeading(
    kind: SpendInsightKind.fuel,
    source: eligible.where((item) => item.category == 'fuel'),
    keyOf: _merchantValue,
    labelOf: _merchantLabel,
    subtype: 'fuel_merchant',
  );

  return results;
}

bool _isMovie(Transaction transaction) {
  return transaction.category == 'entertainment' &&
      (transaction.metadata['platform'] != null ||
          transaction.metadata['merchant_subtype'] == 'movie_platform');
}

String _merchantValue(Transaction transaction) {
  return (transaction.merchantName ?? '').trim().toLowerCase();
}

String _merchantLabel(Transaction transaction) {
  final merchant = transaction.merchantName?.trim();
  return merchant == null || merchant.isEmpty ? 'Unknown merchant' : merchant;
}

String _title(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

_SpendGroup? _leadingGroup(
  Iterable<Transaction> transactions, {
  required String Function(Transaction) keyOf,
  required String Function(Transaction) labelOf,
}) {
  final groups = <String, _SpendGroup>{};
  for (final transaction in transactions) {
    final key = keyOf(transaction);
    if (key.isEmpty) continue;
    final previous = groups[key];
    groups[key] = _SpendGroup(
      key: key,
      label: previous?.label ?? labelOf(transaction),
      amount: (previous?.amount ?? 0) + transaction.amount,
      count: (previous?.count ?? 0) + 1,
    );
  }
  if (groups.isEmpty) return null;
  final ranked = groups.values.toList()
    ..sort((a, b) {
      final amount = b.amount.compareTo(a.amount);
      if (amount != 0) return amount;
      final count = b.count.compareTo(a.count);
      if (count != 0) return count;
      return a.key.compareTo(b.key);
    });
  return ranked.first;
}

class _SpendGroup {
  const _SpendGroup({
    required this.key,
    required this.label,
    required this.amount,
    required this.count,
  });

  final String key;
  final String label;
  final double amount;
  final int count;
}
