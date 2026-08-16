import 'dart:async';

import 'package:cardcompass/core/providers/repository_providers.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/core/repositories/cards_repository.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/cards/screens/add_card_screen.dart';
import 'package:cardcompass/features/cards/screens/cards_screen.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _catalogCard = {
  'id': 'catalog-new',
  'card_name': 'Astra Travel Preferred',
  'bank': 'Horizon Bank',
};

const _user = User(
  id: 'user-1',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-08-16T00:00:00Z',
);

UserCard _card(String id, String name) => UserCard(
  id: id,
  userId: 'user-1',
  catalogCardId: 'catalog-$id',
  cardName: name,
  bank: 'Horizon Bank',
  createdAt: DateTime(2026, 8, 16),
);

class _MemoryCardsRepository extends CardsRepository {
  _MemoryCardsRepository(List<UserCard> initial)
    : cards = [...initial],
      super(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final List<UserCard> cards;
  Completer<void>? saveBarrier;
  bool failNextSave = false;
  var saveCount = 0;
  var loadCount = 0;

  @override
  Future<List<UserCard>> getUserCards(String userId) async {
    loadCount++;
    return [...cards];
  }

  @override
  Future<UserCard> addUserCard({
    required String userId,
    required String catalogCardId,
    String? lastFourDigits,
    String? cardHolderName,
    double? creditLimit,
    int? statementDate,
    int? dueDate,
  }) async {
    saveCount++;
    await saveBarrier?.future;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('private insert failure');
    }
    final card = UserCard(
      id: 'card-new',
      userId: userId,
      catalogCardId: catalogCardId,
      cardName: _catalogCard['card_name'],
      bank: _catalogCard['bank'],
      lastFourDigits: lastFourDigits,
      cardHolderName: cardHolderName,
      createdAt: DateTime(2026, 8, 16),
    );
    cards.add(card);
    return card;
  }
}

Future<GoRouter> _pumpJourney(
  WidgetTester tester, {
  required List<UserCard> initial,
  _MemoryCardsRepository? repository,
}) async {
  repository ??= _MemoryCardsRepository(initial);
  final router = GoRouter(
    initialLocation: '/app/cards',
    routes: [
      GoRoute(path: '/app/cards', builder: (_, _) => const CardsScreen()),
      GoRoute(path: '/app/cards/add', builder: (_, _) => const AddCardScreen()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user),
        cardsRepositoryProvider.overrideWithValue(repository),
        cardCatalogSearchProvider.overrideWithValue(
          (_) async => [_catalogCard],
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.work, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _openAddCard(WidgetTester tester, {required bool empty}) async {
  await tester.tap(empty ? find.text('Add Card') : find.byTooltip('Add card'));
  await tester.pumpAndSettle();
  expect(find.text('Search your card'), findsOneWidget);
}

Future<void> _saveCard(WidgetTester tester) async {
  await _reachConfirmStep(tester);
  await tester.tap(find.text('Add card'));
  await tester.pumpAndSettle();
}

Future<void> _reachConfirmStep(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('card-search')), 'astra');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Astra Travel Preferred'));
  await tester.pumpAndSettle();
}

void main() {
  for (final initial in <List<UserCard>>[
    const [],
    [_card('card-existing', 'Existing card')],
  ]) {
    final startsEmpty = initial.isEmpty;

    testWidgets(
      'add-card Back returns to the ${startsEmpty ? 'empty' : 'populated'} cards list',
      (tester) async {
        final router = await _pumpJourney(tester, initial: initial);
        await _openAddCard(tester, empty: startsEmpty);

        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();

        expect(router.state.uri.path, '/app/cards');
        expect(
          find.text(startsEmpty ? 'No cards yet' : 'Existing card'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'successful save refreshes the ${startsEmpty ? 'empty' : 'populated'} cards list immediately',
      (tester) async {
        final router = await _pumpJourney(tester, initial: initial);
        await _openAddCard(tester, empty: startsEmpty);

        await _saveCard(tester);

        expect(router.state.uri.path, '/app/cards');
        expect(find.text('Astra Travel Preferred'), findsOneWidget);
        if (!startsEmpty) expect(find.text('Existing card'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'pending save can be dismissed immediately and refreshes after success',
    (tester) async {
      final save = Completer<void>();
      final repository = _MemoryCardsRepository(const [])..saveBarrier = save;
      final router = await _pumpJourney(
        tester,
        initial: const [],
        repository: repository,
      );
      await _openAddCard(tester, empty: true);
      await _reachConfirmStep(tester);
      await tester.tap(find.text('Add card'));
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/app/cards');
      expect(find.text('No cards yet'), findsOneWidget);
      expect(repository.saveCount, 1);
      expect(repository.loadCount, 1);

      save.complete();
      await tester.pumpAndSettle();

      expect(find.text('Astra Travel Preferred'), findsOneWidget);
      expect(repository.saveCount, 1);
      expect(repository.loadCount, 2);
    },
  );

  testWidgets('reopening during a pending save cannot insert the card twice', (
    tester,
  ) async {
    final save = Completer<void>();
    final repository = _MemoryCardsRepository(const [])..saveBarrier = save;
    await _pumpJourney(tester, initial: const [], repository: repository);
    await _openAddCard(tester, empty: true);
    await _reachConfirmStep(tester);

    await tester.tap(find.text('Add card'));
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await _openAddCard(tester, empty: true);
    await _reachConfirmStep(tester);
    await tester.tap(find.text('Add card'));
    await tester.pump();

    expect(repository.saveCount, 1);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    save.complete();
    await tester.pumpAndSettle();

    expect(repository.saveCount, 1);
    expect(repository.cards, hasLength(1));
    expect(find.text('Astra Travel Preferred'), findsOneWidget);
  });

  testWidgets(
    'dismissed failed save does not refresh and a dismissed retry can succeed',
    (tester) async {
      final firstSave = Completer<void>();
      final repository = _MemoryCardsRepository(const [])
        ..saveBarrier = firstSave
        ..failNextSave = true;
      await _pumpJourney(tester, initial: const [], repository: repository);
      await _openAddCard(tester, empty: true);
      await _reachConfirmStep(tester);

      await tester.tap(find.text('Add card'));
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      firstSave.complete();
      await tester.pumpAndSettle();

      expect(repository.saveCount, 1);
      expect(repository.loadCount, 1);
      expect(find.text('No cards yet'), findsOneWidget);
      expect(find.textContaining('private insert failure'), findsNothing);

      final retry = Completer<void>();
      repository.saveBarrier = retry;
      await _openAddCard(tester, empty: true);
      await _reachConfirmStep(tester);
      await tester.tap(find.text('Add card'));
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      retry.complete();
      await tester.pumpAndSettle();

      expect(repository.saveCount, 2);
      expect(repository.loadCount, 2);
      expect(repository.cards, hasLength(1));
      expect(find.text('Astra Travel Preferred'), findsOneWidget);
    },
  );
}
