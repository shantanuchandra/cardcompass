import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/features/dashboard/providers/dashboard_provider.dart';
import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:cardcompass/features/dashboard/providers/imported_data_refresh_provider.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const emptyDashboardData = DashboardData(
  cards: [],
  recentTransactions: [],
  latestStatements: {},
  totalCreditLimit: 0,
  monthlySpend: 0,
  rewardsEarned: 0,
  monthlySpendTrend: [],
  monthlyRewardsTrend: [],
  trendMonths: [],
);

int txnLoads = 0;

class CountingTxnsNotifier extends TxnsNotifier {
  @override
  Future<TxnsState> build() async {
    txnLoads++;
    return const TxnsState();
  }
}

void main() {
  test('refreshes every imported-data provider after statement sync', () async {
    var dashboardLoads = 0;
    var cardsLoads = 0;
    var pendingLoads = 0;

    final container = ProviderContainer(
      overrides: [
        dashboardProvider.overrideWith((ref) async {
          dashboardLoads++;
          return emptyDashboardData;
        }),
        userCardsProvider.overrideWith((ref) async {
          cardsLoads++;
          return const [];
        }),
        txnsNotifierProvider.overrideWith(CountingTxnsNotifier.new),
        pendingCardAssignmentsProvider.overrideWith((ref) async {
          pendingLoads++;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    await Future.wait([
      container.read(dashboardProvider.future),
      container.read(userCardsProvider.future),
      container.read(txnsNotifierProvider.future),
      container.read(pendingCardAssignmentsProvider.future),
    ]);

    container.read(importedDataRefreshProvider)();

    await Future.wait([
      container.read(dashboardProvider.future),
      container.read(userCardsProvider.future),
      container.read(txnsNotifierProvider.future),
      container.read(pendingCardAssignmentsProvider.future),
    ]);

    expect((dashboardLoads, cardsLoads, txnLoads, pendingLoads), (2, 2, 2, 2));
  });
}
