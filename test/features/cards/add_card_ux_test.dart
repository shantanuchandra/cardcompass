import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/cards/screens/add_card_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _catalogCard = {
  'id': 'catalog-1',
  'card_name': 'Astra Travel Preferred',
  'bank': 'Horizon Bank',
};

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
}
