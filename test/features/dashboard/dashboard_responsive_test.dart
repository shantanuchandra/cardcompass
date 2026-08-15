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

Future<void> pumpDashboard(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        pendingCardAssignmentsProvider.overrideWith((ref) async => []),
        dashboardProvider.overrideWith((ref) async => _fixture),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: AppTabSelection(
            onSelect: (_) {},
            child: const DashboardScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'monthly spend is primary and supporting metrics stack at scale',
    (tester) async {
      await pumpDashboard(tester, width: 390, textScale: 2);

      final spend = find.byKey(const Key('primary-spend-metric'));
      final rewards = find.byKey(const Key('supporting-rewards-metric'));
      final limit = find.byKey(const Key('supporting-limit-metric'));
      expect(spend, findsOneWidget);
      expect(rewards, findsOneWidget);
      expect(limit, findsOneWidget);
      expect(
        tester.getTopLeft(limit).dy,
        greaterThan(tester.getTopLeft(rewards).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'dashboard hierarchy remains usable at ${width.toInt()}px / $textScale×',
        (tester) async {
          await pumpDashboard(tester, width: width, textScale: textScale);

          expect(find.byKey(const Key('primary-spend-metric')), findsOneWidget);
          expect(
            find.byKey(const Key('supporting-rewards-metric')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('supporting-limit-metric')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
