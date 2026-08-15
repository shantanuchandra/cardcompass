import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/cards/screens/card_detail_screen.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _card = UserCard(
  id: 'card-1',
  userId: 'user-1',
  catalogCardId: 'catalog-1',
  cardName: 'A very long preferred travel rewards card name',
  bank: 'Horizon Bank',
  lastFourDigits: '4242',
  creditLimit: 250000,
  annualFee: 999,
  dueDate: 22,
  statementDate: 5,
  createdAt: DateTime(2026),
);

Future<void> pumpDetail(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        cardDetailProvider('card-1').overrideWith((ref) async => _card),
        cardTransactionsProvider('card-1').overrideWith((ref) async => []),
        cardStatementProvider('card-1').overrideWith((ref) async => null),
        cardMonthSpendProvider('card-1').overrideWith((ref) async => 0),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const CardDetailScreen(cardId: 'card-1'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('detail puts decisions before disclosures', (tester) async {
    await pumpDetail(tester);

    final headings = [
      'Card summary',
      'Best uses',
      'Milestone',
      'Current bill',
      'Rewards & fees',
      'History',
    ];
    for (final heading in headings) {
      expect(find.text(heading), findsOneWidget);
    }
    for (var index = 1; index < headings.length; index++) {
      expect(
        tester.getTopLeft(find.text(headings[index - 1])).dy,
        lessThan(tester.getTopLeft(find.text(headings[index])).dy),
      );
    }

    await tester.tap(find.text('Rewards & fees'));
    await tester.pumpAndSettle();
    expect(find.text('Annual fee'), findsOneWidget);
  });

  testWidgets('detail remains usable with long names at 200% scale', (
    tester,
  ) async {
    await pumpDetail(tester, textScale: 2);

    expect(find.text(_card.displayName), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
