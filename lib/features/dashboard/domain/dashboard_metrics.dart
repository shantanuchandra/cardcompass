import '../../../core/services/retail_transaction_aggregation.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/user_card.dart';

class DashboardMetrics {
  const DashboardMetrics({
    required this.totalReportedCardLimits,
    required this.monthlySpendTrend,
    required this.monthlyRewardsTrend,
  });

  final double totalReportedCardLimits;
  final List<double> monthlySpendTrend;
  final List<double> monthlyRewardsTrend;
}

/// Computes the three dashboard metric cards from normalized rows.
///
/// Spend and rewards use unique billed retail purchases only. Payments,
/// credits, unlinked refunds, fees, interest, rewards, cash withdrawals,
/// invalid values, and dates outside the reporting window are excluded.
/// Refunds can reduce spend only after they are reliably linked to a purchase;
/// CardCompass does not currently persist that relationship, so they are not
/// guessed into a month. Transaction duplicates use the same natural key as
/// the database's `idx_transactions_dedup` index.
DashboardMetrics calculateDashboardMetrics({
  required List<UserCard> cards,
  required List<Transaction> transactions,
  required DateTime trendStart,
  required DateTime periodEnd,
  required int monthCount,
}) {
  final seenCardIds = <String>{};
  var totalReportedCardLimits = 0.0;
  for (final card in cards) {
    if (!card.isActive || !seenCardIds.add(card.id)) continue;
    final limit = card.creditLimit;
    if (limit == null || !limit.isFinite || limit <= 0) continue;
    totalReportedCardLimits += limit;
  }

  final monthlySpendTrend = List<double>.filled(monthCount, 0);
  final monthlyRewardsTrend = List<double>.filled(monthCount, 0);
  final aggregate = aggregateRetailTransactions(
    transactions,
    fromInclusive: trendStart,
    throughInclusive: periodEnd,
  );

  for (final transaction in aggregate.purchases) {
    final monthIndex =
        (transaction.transactionDate.year - trendStart.year) * 12 +
        (transaction.transactionDate.month - trendStart.month);
    if (monthIndex < 0 || monthIndex >= monthCount) continue;

    monthlySpendTrend[monthIndex] += transaction.amount;
    monthlyRewardsTrend[monthIndex] += aggregate.rewardFor(transaction);
  }

  return DashboardMetrics(
    totalReportedCardLimits: totalReportedCardLimits,
    monthlySpendTrend: monthlySpendTrend,
    monthlyRewardsTrend: monthlyRewardsTrend,
  );
}
