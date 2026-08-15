import 'package:cardcompass/core/theme/app_theme.dart';
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
