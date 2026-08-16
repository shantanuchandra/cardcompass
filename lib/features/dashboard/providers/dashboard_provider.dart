import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';

const trendMonthCount = 6;

class DashboardData {
  final List<UserCard> cards;
  final List<Transaction> recentTransactions;
  final Map<String, Statement> latestStatements;
  final double totalCreditLimit;
  final double monthlySpend;
  final double rewardsEarned;

  /// Oldest-to-newest total debit spend for the last [trendMonthCount]
  /// months (last element is the current, in-progress month).
  final List<double> monthlySpendTrend;

  /// Oldest-to-newest total rewards earned for the same window.
  final List<double> monthlyRewardsTrend;

  const DashboardData({
    required this.cards,
    required this.recentTransactions,
    required this.latestStatements,
    required this.totalCreditLimit,
    required this.monthlySpend,
    required this.rewardsEarned,
    required this.monthlySpendTrend,
    required this.monthlyRewardsTrend,
  });
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw StateError('Not authenticated');

  final cardsRepo = ref.read(cardsRepositoryProvider);
  final txnRepo = ref.read(transactionsRepositoryProvider);
  final stmtRepo = ref.read(statementsRepositoryProvider);

  final now = DateTime.now();
  final trendStart = DateTime(now.year, now.month - (trendMonthCount - 1), 1);

  final results = await Future.wait([
    cardsRepo.getUserCards(user.id),
    txnRepo.getRecentTransactions(user.id, limit: 12),
    txnRepo.getTransactions(
      userId: user.id,
      from: trendStart,
      to: now,
      limit: 2000,
    ),
    stmtRepo.getLatestStatementPerCard(user.id),
  ]);

  final cards = results[0] as List<UserCard>;
  final recent = results[1] as List<Transaction>;
  final trendTxns = results[2] as List<Transaction>;
  final stmts = results[3] as Map<String, Statement>;

  final totalLimit = cards.fold<double>(0, (s, c) => s + (c.creditLimit ?? 0));

  final spendByMonth = List<double>.filled(trendMonthCount, 0);
  final rewardsByMonth = List<double>.filled(trendMonthCount, 0);
  for (final t in trendTxns) {
    final monthIndex =
        (t.transactionDate.year - trendStart.year) * 12 +
        (t.transactionDate.month - trendStart.month);
    if (monthIndex < 0 || monthIndex >= trendMonthCount) continue;
    if (t.isDebit) spendByMonth[monthIndex] += t.amount;
    rewardsByMonth[monthIndex] += t.rewardEarned ?? 0;
  }

  return DashboardData(
    cards: cards,
    recentTransactions: recent,
    latestStatements: stmts,
    totalCreditLimit: totalLimit,
    monthlySpend: spendByMonth.last,
    rewardsEarned: rewardsByMonth.last,
    monthlySpendTrend: spendByMonth,
    monthlyRewardsTrend: rewardsByMonth,
  );
});
