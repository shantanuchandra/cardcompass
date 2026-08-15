import 'dart:io';

import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/core/router/app_tab_selection.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/dashboard/providers/dashboard_provider.dart';
import 'package:cardcompass/features/dashboard/providers/gmail_sync_provider.dart';
import 'package:cardcompass/features/dashboard/screens/dashboard_screen.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixture = DashboardData(
  cards: [
    UserCard(
      id: 'card-1',
      userId: 'user-1',
      catalogCardId: 'catalog-1',
      cardName: 'Horizon Card',
      bank: 'Horizon Bank',
      creditLimit: 100000,
      createdAt: DateTime(2026),
    ),
  ],
  recentTransactions: [
    Transaction(
      id: 'transaction-1',
      userId: 'user-1',
      userCardId: 'card-1',
      amount: 1250,
      description: 'Groceries',
      transactionType: TransactionType.debit,
      transactionDate: DateTime(2026, 8, 15),
      createdAt: DateTime(2026, 8, 15),
    ),
  ],
  latestStatements: {},
  totalCreditLimit: 100000,
  monthlySpend: 1250,
  rewardsEarned: 75,
);

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required ValueNotifier<AppTab> selectedAppTab,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        pendingCardAssignmentsProvider.overrideWith((ref) async => []),
        dashboardProvider.overrideWith((ref) async => _fixture),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: AppTabSelection(
          onSelect: (tab) => selectedAppTab.value = tab,
          child: const DashboardScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final source = File(
    'lib/features/dashboard/screens/dashboard_screen.dart',
  ).readAsStringSync();
  test('dashboard is an ink and paper wallet briefing', () {
    expect(source, contains('BrandColors.paper'));
    expect(source, contains('BrandColors.ledger'));
    expect(source, contains("fontFamily: 'Fraunces'"));
    expect(source, isNot(contains('GoogleFonts.spaceGrotesk')));
  });

  testWidgets('dashboard view-all actions select their destinations', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(tester, selectedAppTab: selectedAppTab);

    await tester.scrollUntilVisible(
      find.text('Manage cards'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Manage cards'));
    expect(selectedAppTab.value, AppTab.cards);

    await tester.scrollUntilVisible(
      find.text('View all transactions'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('View all transactions'));
    expect(selectedAppTab.value, AppTab.transactions);
    await tester.pump(const Duration(milliseconds: 300));
  });
}
