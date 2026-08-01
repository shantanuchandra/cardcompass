import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/user_card.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/statement.dart';

class DashboardData {
  final List<UserCard> cards;
  final List<Transaction> recentTransactions;
  final Map<String, Statement> latestStatements;
  final double totalCreditLimit;
  final double monthlySpend;
  final double rewardsEarned;

  const DashboardData({
    required this.cards,
    required this.recentTransactions,
    required this.latestStatements,
    required this.totalCreditLimit,
    required this.monthlySpend,
    required this.rewardsEarned,
  });
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw StateError('Not authenticated');

  final cardsRepo = ref.read(cardsRepositoryProvider);
  final txnRepo = ref.read(transactionsRepositoryProvider);
  final stmtRepo = ref.read(statementsRepositoryProvider);

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);

  final results = await Future.wait([
    cardsRepo.getUserCards(user.id),
    txnRepo.getRecentTransactions(user.id, limit: 12),
    txnRepo.getTransactions(userId: user.id, from: monthStart, to: now, limit: 500),
    stmtRepo.getLatestStatementPerCard(user.id),
  ]);

  final cards = results[0] as List<UserCard>;
  final recent = results[1] as List<Transaction>;
  final monthTxns = results[2] as List<Transaction>;
  final stmts = results[3] as Map<String, Statement>;

  final totalLimit = cards.fold<double>(0, (s, c) => s + (c.creditLimit ?? 0));
  final spend = monthTxns.where((t) => t.isDebit).fold<double>(0, (s, t) => s + t.amount);
  final rewards = monthTxns.fold<double>(0, (s, t) => s + (t.rewardEarned ?? 0));

  return DashboardData(
    cards: cards,
    recentTransactions: recent,
    latestStatements: stmts,
    totalCreditLimit: totalLimit,
    monthlySpend: spend,
    rewardsEarned: rewards,
  );
});
