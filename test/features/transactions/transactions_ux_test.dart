import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/features/transactions/screens/transactions_screen.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _card = UserCard(
  id: 'card-1',
  userId: 'user-1',
  catalogCardId: 'catalog-1',
  cardName: 'A very long travel rewards card name',
  lastFourDigits: '4242',
  createdAt: DateTime(2026),
);

final _transaction = Transaction(
  id: 'transaction-1',
  userId: 'user-1',
  userCardId: 'card-1',
  amount: 1834,
  description: 'Long merchant backup description',
  merchantName:
      'An exceptionally long merchant name that should remain accessible',
  category: 'Dining',
  transactionType: TransactionType.debit,
  transactionDate: DateTime(2026, 8, 15, 14, 30),
  rewardEarned: 36,
  createdAt: DateTime(2026, 8, 15),
);

class _LedgerNotifier extends TxnsNotifier {
  _LedgerNotifier(this.load);

  final Future<TxnsState> Function() load;

  @override
  Future<TxnsState> build() => load();
}

Future<void> pumpLedger(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  Future<TxnsState> Function()? load,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        txnsNotifierProvider.overrideWith(
          () => _LedgerNotifier(
            load ?? () async => TxnsState(all: [_transaction], cards: [_card]),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const TransactionsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ledger redacts repository failures and offers recovery', (
    tester,
  ) async {
    await pumpLedger(
      tester,
      width: 390,
      load: () async => throw StateError('postgrest table failure'),
    );

    expect(find.textContaining('postgrest'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('filters open in a sheet on narrow screens', (tester) async {
    await pumpLedger(tester, width: 390);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('ledger makes spend the primary metric', (tester) async {
    await pumpLedger(tester, width: 768);

    expect(find.byType(BrandMetric), findsOneWidget);
    expect(find.text('Total spend'), findsOneWidget);
    expect(find.text('Rewards earned'), findsOneWidget);
    final metricText = find.descendant(
      of: find.byType(BrandMetric),
      matching: find.byType(Text),
    );
    final primary = tester
        .widgetList<Text>(metricText)
        .firstWhere((text) => text.style?.fontFamily == 'IBM Plex Mono');
    final rewards = tester.widget<Text>(find.text('Rewards earned'));
    expect(primary.style!.fontSize, greaterThan(rewards.style!.fontSize!));
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final textScale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'ledger keeps long merchant names usable at ${width.toInt()}px and ${textScale}x text',
        (tester) async {
          await pumpLedger(tester, width: width, textScale: textScale);

          final merchant = find.text(_transaction.merchantName!);
          await tester.scrollUntilVisible(
            merchant,
            400,
            scrollable: find.byType(Scrollable).last,
          );
          expect(merchant, findsOneWidget);
          expect(
            tester.getSemantics(merchant).label,
            contains(_transaction.merchantName),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
