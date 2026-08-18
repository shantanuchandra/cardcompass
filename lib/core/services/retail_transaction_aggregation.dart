import '../../shared/models/transaction.dart';
import 'eligible_spend.dart';

class RetailTransactionAggregate {
  const RetailTransactionAggregate._({
    required this.purchases,
    required this.totalSpend,
    required this.totalRewards,
    required this.categoryTotals,
    required this.localDayTotals,
    required this._rewardsByPurchase,
  });

  final List<Transaction> purchases;
  final double totalSpend;
  final double totalRewards;
  final Map<String, double> categoryTotals;
  final Map<DateTime, double> localDayTotals;
  final Map<Transaction, double> _rewardsByPurchase;

  double rewardFor(Transaction purchase) => _rewardsByPurchase[purchase] ?? 0;
}

RetailTransactionAggregate aggregateRetailTransactions(
  Iterable<Transaction> rows, {
  DateTime? fromInclusive,
  DateTime? throughInclusive,
}) {
  final purchases = <Transaction>[];
  final seen = <(String, String, int, String, double)>{};
  final categoryTotals = <String, double>{};
  final localDayTotals = <DateTime, double>{};
  final rewardsByPurchase = <Transaction, double>{};
  var totalSpend = 0.0;
  var totalRewards = 0.0;

  for (final transaction in rows) {
    final date = transaction.transactionDate;
    if (fromInclusive != null && date.isBefore(fromInclusive)) continue;
    if (throughInclusive != null && date.isAfter(throughInclusive)) continue;
    if (!isEligibleRetailSpend(transaction) ||
        !transaction.amount.isFinite ||
        transaction.amount <= 0) {
      continue;
    }

    final naturalKey = (
      transaction.userId,
      transaction.userCardId,
      date.microsecondsSinceEpoch,
      transaction.description,
      transaction.amount,
    );
    if (!seen.add(naturalKey)) continue;

    purchases.add(transaction);
    totalSpend += transaction.amount;

    final category = transaction.category ?? 'Other';
    categoryTotals[category] =
        (categoryTotals[category] ?? 0) + transaction.amount;

    final localDate = date.toLocal();
    final localDay = DateTime(localDate.year, localDate.month, localDate.day);
    localDayTotals[localDay] =
        (localDayTotals[localDay] ?? 0) + transaction.amount;

    final reward = transaction.rewardEarned;
    final eligibleReward = reward != null && reward.isFinite && reward > 0
        ? reward
        : 0.0;
    rewardsByPurchase[transaction] = eligibleReward;
    totalRewards += eligibleReward;
  }

  return RetailTransactionAggregate._(
    purchases: List.unmodifiable(purchases),
    totalSpend: totalSpend,
    totalRewards: totalRewards,
    categoryTotals: Map.unmodifiable(categoryTotals),
    localDayTotals: Map.unmodifiable(localDayTotals),
    rewardsByPurchase: Map.unmodifiable(rewardsByPurchase),
  );
}
