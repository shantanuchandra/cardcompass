import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';
import '../domain/dashboard_metrics.dart';

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

  /// The first day of each month in [monthlySpendTrend] /
  /// [monthlyRewardsTrend], oldest → newest, same length as both — lets the
  /// UI label a bar with its real calendar month instead of assuming one.
  final List<DateTime> trendMonths;

  const DashboardData({
    required this.cards,
    required this.recentTransactions,
    required this.latestStatements,
    required this.totalCreditLimit,
    required this.monthlySpend,
    required this.rewardsEarned,
    required this.monthlySpendTrend,
    required this.monthlyRewardsTrend,
    required this.trendMonths,
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
    txnRepo.getAllTransactionsInRange(
      userId: user.id,
      from: trendStart,
      to: now,
    ),
    stmtRepo.getLatestStatementPerCard(user.id),
  ]);

  final cards = results[0] as List<UserCard>;
  final recent = results[1] as List<Transaction>;
  final trendTxns = results[2] as List<Transaction>;
  final stmts = results[3] as Map<String, Statement>;

  final metrics = calculateDashboardMetrics(
    cards: cards,
    transactions: trendTxns,
    trendStart: trendStart,
    periodEnd: now,
    monthCount: trendMonthCount,
  );

  final trendMonths = List<DateTime>.generate(
    trendMonthCount,
    (i) => DateTime(trendStart.year, trendStart.month + i, 1),
  );

  return DashboardData(
    cards: cards,
    recentTransactions: recent,
    latestStatements: stmts,
    totalCreditLimit: metrics.totalReportedCardLimits,
    monthlySpend: metrics.monthlySpendTrend.last,
    rewardsEarned: metrics.monthlyRewardsTrend.last,
    monthlySpendTrend: metrics.monthlySpendTrend,
    monthlyRewardsTrend: metrics.monthlyRewardsTrend,
    trendMonths: trendMonths,
  );
});
