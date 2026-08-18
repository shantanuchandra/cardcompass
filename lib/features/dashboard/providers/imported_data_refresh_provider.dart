import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cards/providers/cards_provider.dart';
import '../../cards/screens/card_detail_screen.dart';
import '../../transactions/providers/transactions_provider.dart';
import 'dashboard_provider.dart';
import 'gmail_sync_provider.dart';

typedef ImportedDataRefresh = void Function();

final importedDataRefreshProvider = Provider<ImportedDataRefresh>((ref) {
  return () {
    ref.invalidate(dashboardProvider);
    ref.invalidate(userCardsProvider);
    ref.invalidate(latestCardStatementsProvider);
    ref.invalidate(txnsNotifierProvider);
    ref.invalidate(pendingCardAssignmentsProvider);
    ref.invalidate(cardDetailProvider);
    ref.invalidate(cardTransactionsProvider);
    ref.invalidate(cardStatementProvider);
    ref.invalidate(cardStatementArchiveProvider);
    ref.invalidate(cardMonthSpendProvider);
  };
});
