import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/cards/screens/cards_screen.dart';
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
}
