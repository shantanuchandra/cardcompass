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

final _cardlessFixture = DashboardData(
  cards: const [],
  recentTransactions: const [],
  latestStatements: const {},
  totalCreditLimit: 0,
  monthlySpend: 0,
  rewardsEarned: 0,
);

class _FailingGmailSyncNotifier extends GmailSyncNotifier {
  @override
  Future<GmailSyncResult?> build() async {
    throw StateError('internal Gmail credential must not be displayed');
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required ValueNotifier<AppTab> selectedAppTab,
  DashboardData? data,
  bool failDashboard = false,
  bool failGmailSync = false,
  VoidCallback? onDashboardLoad,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        pendingCardAssignmentsProvider.overrideWith((ref) async => []),
        dashboardProvider.overrideWith((ref) async {
          onDashboardLoad?.call();
          if (failDashboard) {
            throw StateError(
              'internal dashboard request must not be displayed',
            );
          }
          return data ?? _fixture;
        }),
        if (failGmailSync)
          gmailSyncProvider.overrideWith(_FailingGmailSyncNotifier.new),
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

  testWidgets('cardless dashboard focuses one setup action for Cards', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      data: _cardlessFixture,
    );

    expect(find.text('Build your dashboard'), findsOneWidget);
    expect(find.byKey(const Key('primary-spend-metric')), findsNothing);
    await tester.tap(find.text('Add a card'));
    expect(selectedAppTab.value, AppTab.cards);
  });

  testWidgets('dashboard failures redact internal details and offer Retry', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    var dashboardLoads = 0;
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      failDashboard: true,
      onDashboardLoad: () => dashboardLoads++,
    );

    expect(find.text("Couldn't load dashboard"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.textContaining('internal dashboard request'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(dashboardLoads, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(dashboardLoads, 2);
  });

  testWidgets('primary recent-spending action selects Transactions', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(tester, selectedAppTab: selectedAppTab);

    await tester.tap(find.text('Review recent spending'));
    expect(selectedAppTab.value, AppTab.transactions);
  });

  testWidgets('Gmail sync failures never render internal exception text', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(
      tester,
      selectedAppTab: selectedAppTab,
      failGmailSync: true,
    );

    expect(
      find.textContaining('internal Gmail credential must not be displayed'),
      findsNothing,
    );
    expect(
      find.text("Couldn't sync Gmail. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('dashboard card is a labeled keyboard-sized button', (
    tester,
  ) async {
    final selectedAppTab = ValueNotifier(AppTab.dashboard);
    addTearDown(selectedAppTab.dispose);
    await _pumpDashboard(tester, selectedAppTab: selectedAppTab);

    final card = find.byKey(const Key('dashboard-card-card-1'));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.getSize(card).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(card),
      matchesSemantics(
        label: 'Open Horizon Card card details',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  });
}
