import 'dart:async';

import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/cards/screens/cards_screen.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final card = UserCard(
    id: 'card-1',
    userId: 'user-1',
    catalogCardId: 'catalog-1',
    cardName: 'A very long preferred travel rewards card name',
    bank: 'Horizon Bank',
    lastFourDigits: '4242',
    creditLimit: 250000,
    createdAt: DateTime(2026),
  );

  testWidgets('card list shows a complete, readable identity at 200% scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          userCardsProvider.overrideWith((ref) async => [card]),
        ],
        child: MaterialApp(
          theme: AppTheme.work,
          home: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: CardsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CardIdentityMark), findsOneWidget);
    expect(find.text(card.displayName), findsOneWidget);
    expect(find.text('Horizon Bank · •••• 4242'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('₹2.5L limit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'card load failures keep backend details private and offer retry',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(null),
            userCardsProvider.overrideWith(
              (ref) async =>
                  throw StateError('private card repository failure'),
            ),
          ],
          child: MaterialApp(theme: AppTheme.work, home: const CardsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load your cards.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(
        find.textContaining('private card repository failure'),
        findsNothing,
      );
    },
  );

  testWidgets('card loading reserves a stable skeleton slot', (tester) async {
    final pending = Completer<List<UserCard>>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete([]);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          userCardsProvider.overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(theme: AppTheme.work, home: const CardsScreen()),
      ),
    );
    await tester.pump();

    final loading = find.byKey(const Key('cards-loading'));
    expect(loading, findsOneWidget);
    expect(tester.getSize(loading).height, greaterThanOrEqualTo(240));
    expect(find.bySemanticsLabel('Loading your cards'), findsOneWidget);
  });
}
