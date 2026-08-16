import 'dart:async';

import 'package:cardcompass/core/providers/repository_providers.dart';
import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/core/repositories/cards_repository.dart';
import 'package:cardcompass/features/cards/screens/add_card_screen.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _catalogCard = {
  'id': 'catalog-1',
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

class _SavingCardsRepository extends CardsRepository {
  _SavingCardsRepository()
    : super(
        SupabaseClient(
          'http://localhost',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  var saveCount = 0;
  Completer<void>? pendingSave;

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
    await pendingSave?.future;
    return UserCard(
      id: 'saved-card',
      userId: userId,
      catalogCardId: catalogCardId,
      createdAt: DateTime(2026, 8, 16),
    );
  }
}

Future<void> pumpAddCard(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        cardCatalogSearchProvider.overrideWithValue(
          (query) async => [_catalogCard],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const AddCardScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reachConfirmStep(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('card-search')), 'astra');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Astra Travel Preferred'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add card exposes search and confirm progress', (tester) async {
    await pumpAddCard(tester);

    expect(find.text('1 Search'), findsOneWidget);
    expect(find.text('2 Confirm'), findsOneWidget);
  });

  testWidgets('progress marks Confirm as the current step after selection', (
    tester,
  ) async {
    await pumpAddCard(tester);
    await reachConfirmStep(tester);

    expect(
      find.bySemanticsLabel('Add card progress. Current step: Confirm'),
      findsOneWidget,
    );
  });

  testWidgets('last four explains optional use and rejects non-four digits', (
    tester,
  ) async {
    await pumpAddCard(tester);
    await reachConfirmStep(tester);

    expect(
      find.text(
        'Optional — helps match statements to this card. We never ask for the full card number.',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('last-four')), '12');
    await tester.tap(find.text('Add card'));
    await tester.pump();

    expect(
      find.text('Enter exactly four digits or leave this blank'),
      findsOneWidget,
    );
  });

  testWidgets(
    'last four keeps blank and valid values clear, but marks invalid input inline',
    (tester) async {
      await pumpAddCard(tester);
      await reachConfirmStep(tester);
      final input = find.byKey(const Key('last-four'));

      await tester.tap(find.text('Add card'));
      expect(tester.widget<TextField>(input).decoration!.errorText, isNull);

      await tester.enterText(input, '1234');
      await tester.tap(find.text('Add card'));
      expect(tester.widget<TextField>(input).decoration!.errorText, isNull);

      await tester.enterText(input, '12');
      await tester.tap(find.text('Add card'));
      await tester.pump();
      expect(
        tester.widget<TextField>(input).decoration!.errorText,
        'Enter exactly four digits or leave this blank',
      );
      expect(
        find.text('Enter exactly four digits or leave this blank'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byKey(const Key('last-four-field'))).label,
        contains('Enter exactly four digits or leave this blank'),
      );
    },
  );

  testWidgets('catalogue errors are actionable and do not expose internals', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardCatalogSearchProvider.overrideWithValue(
            (query) async => throw StateError('private catalog connection'),
          ),
        ],
        child: MaterialApp(theme: AppTheme.work, home: const AddCardScreen()),
      ),
    );
    await tester.enterText(find.byKey(const Key('card-search')), 'astra');
    await tester.pumpAndSettle();

    expect(
      find.text('Could not search the card catalogue. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private catalog connection'), findsNothing);
    expect(find.text('Retry search'), findsOneWidget);
  });

  testWidgets('changing selection keeps the search query available', (
    tester,
  ) async {
    await pumpAddCard(tester);
    await reachConfirmStep(tester);

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('card-search')),
    );
    expect(field.controller!.text, 'astra');
  });

  testWidgets('confirm step remains usable at 390px and 200% text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAddCard(tester, textScale: 2);
    await reachConfirmStep(tester);

    expect(find.byKey(const Key('last-four')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'newest catalogue query wins when responses complete out of order',
    (tester) async {
      final first = Completer<List<Map<String, dynamic>>>();
      final second = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardCatalogSearchProvider.overrideWithValue((query) {
              return query == 'as' ? first.future : second.future;
            }),
          ],
          child: MaterialApp(theme: AppTheme.work, home: const AddCardScreen()),
        ),
      );

      await tester.enterText(find.byKey(const Key('card-search')), 'as');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('card-search')), 'astra');
      await tester.pump();

      second.complete([
        const {'id': 'new', 'card_name': 'Newest result', 'bank': 'New Bank'},
      ]);
      await tester.pump();
      first.complete([
        const {'id': 'old', 'card_name': 'Stale result', 'bank': 'Old Bank'},
      ]);
      await tester.pump();

      expect(find.text('Newest result'), findsOneWidget);
      expect(find.text('Stale result'), findsNothing);
    },
  );

  testWidgets(
    'short query clears loading, errors, results, and ignores in-flight work',
    (tester) async {
      final pending = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardCatalogSearchProvider.overrideWithValue((query) async {
              if (query == 'error') throw StateError('private search detail');
              return pending.future;
            }),
          ],
          child: MaterialApp(theme: AppTheme.work, home: const AddCardScreen()),
        ),
      );

      await tester.enterText(find.byKey(const Key('card-search')), 'error');
      await tester.pumpAndSettle();
      expect(find.text('Retry search'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('card-search')), 'as');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.enterText(find.byKey(const Key('card-search')), 'a');
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry search'), findsNothing);
      pending.complete([
        const {'id': 'late', 'card_name': 'Late result', 'bank': 'Late Bank'},
      ]);
      await tester.pump();
      expect(find.text('Late result'), findsNothing);
    },
  );

  testWidgets(
    'search and save completions after disposal do not update state',
    (tester) async {
      final search = Completer<List<Map<String, dynamic>>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardCatalogSearchProvider.overrideWithValue((_) => search.future),
          ],
          child: MaterialApp(theme: AppTheme.work, home: const AddCardScreen()),
        ),
      );
      await tester.enterText(find.byKey(const Key('card-search')), 'as');
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      search.complete(const []);
      await tester.pump();
      expect(tester.takeException(), isNull);

      final repository = _SavingCardsRepository()
        ..pendingSave = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_user),
            cardsRepositoryProvider.overrideWithValue(repository),
            cardCatalogSearchProvider.overrideWithValue(
              (_) async => [_catalogCard],
            ),
          ],
          child: MaterialApp(theme: AppTheme.work, home: const AddCardScreen()),
        ),
      );
      await reachConfirmStep(tester);
      await tester.tap(find.text('Add card'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      repository.pendingSave!.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful insert is not reported as an error when no route can pop',
    (tester) async {
      final repository = _SavingCardsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_user),
            cardsRepositoryProvider.overrideWithValue(repository),
            cardCatalogSearchProvider.overrideWithValue(
              (_) async => [_catalogCard],
            ),
          ],
          child: MaterialApp(theme: AppTheme.work, home: const AddCardScreen()),
        ),
      );
      await reachConfirmStep(tester);
      await tester.tap(find.text('Add card'));
      await tester.pumpAndSettle();

      expect(repository.saveCount, 1);
      expect(find.text('Could not add this card. Try again.'), findsNothing);
      expect(find.textContaining('Card added'), findsOneWidget);
    },
  );
}
