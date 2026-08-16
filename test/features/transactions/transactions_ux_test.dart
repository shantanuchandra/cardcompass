import 'dart:async';

import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/theme/brand_components.dart';
import 'package:cardcompass/features/transactions/providers/transactions_provider.dart';
import 'package:cardcompass/features/transactions/screens/transactions_screen.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/user_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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

final _travelTransaction = Transaction(
  id: 'transaction-2',
  userId: 'user-1',
  userCardId: 'card-1',
  amount: 920,
  description: 'Second merchant backup description',
  merchantName: 'Second merchant',
  category: 'Travel',
  transactionType: TransactionType.debit,
  transactionDate: DateTime(2026, 8, 16, 9),
  rewardEarned: 17,
  createdAt: DateTime(2026, 8, 16),
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
  testWidgets('transaction destination uses one consistent user-facing name', (
    tester,
  ) async {
    await pumpLedger(tester, width: 390, load: () async => const TxnsState());

    expect(find.text('Transactions'), findsOneWidget);
    expect(find.textContaining('ledger', findRichText: true), findsNothing);
  });

  testWidgets('ledger loading reserves a stable skeleton slot', (tester) async {
    final pending = Completer<TxnsState>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const TxnsState());
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          txnsNotifierProvider.overrideWith(
            () => _LedgerNotifier(() => pending.future),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.work,
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pump();

    final loading = find.byKey(const Key('transactions-loading'));
    expect(loading, findsOneWidget);
    expect(tester.getSize(loading).height, greaterThanOrEqualTo(240));
  });

  testWidgets('ledger distinguishes dataset-empty from filtered-empty', (
    tester,
  ) async {
    await pumpLedger(tester, width: 390, load: () async => const TxnsState());
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Check again'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLedger(
      tester,
      width: 390,
      load: () async => TxnsState(
        all: [_transaction],
        cards: [_card],
        filter: const TxnFilter(category: 'Travel'),
      ),
    );
    expect(find.text('No matches for these filters'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text(_transaction.merchantName!), findsOneWidget);
  });

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

  testWidgets('filter and grouping controls expose 44px keyboard actions', (
    tester,
  ) async {
    await pumpLedger(tester, width: 390);

    final filters = find.byKey(const Key('transactions-filters'));
    final grouping = find.byKey(const Key('transactions-grouping'));
    expect(tester.getSize(filters).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(grouping).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(filters),
      matchesSemantics(
        label: 'Filters, All time',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
        hasTapAction: true,
      ),
    );

    for (
      var index = 0;
      index < 8 && find.byType(BottomSheet).evaluate().isEmpty;
      index++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }
    expect(find.byType(BottomSheet), findsOneWidget);

    final allTime = find.byKey(const Key('date-filter-All time'));
    expect(tester.getSize(allTime).height, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(allTime),
      matchesSemantics(
        label: 'All time',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
  });

  for (final textScale in [1.5, 2.0]) {
    testWidgets(
      'filters keep their active count visible at ${textScale}x text',
      (tester) async {
        await pumpLedger(
          tester,
          width: 390,
          textScale: textScale,
          load: () async => TxnsState(
            all: [_transaction],
            cards: [_card],
            filter: TxnFilter(from: DateTime(2026, 8, 1)),
          ),
        );

        final count = find.text('1 active');
        expect(count, findsOneWidget);
        expect(tester.getRect(count).right, lessThanOrEqualTo(390));
        expect(tester.takeException(), isNull);
      },
    );
  }

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

  testWidgets('reordered rows retain their own expanded details state', (
    tester,
  ) async {
    await pumpLedger(
      tester,
      width: 768,
      load: () async =>
          TxnsState(all: [_travelTransaction, _transaction], cards: [_card]),
    );

    await tester.scrollUntilVisible(
      find.text('Details').last,
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Details').last);
    await tester.pumpAndSettle();
    expect(find.text('+36 pts'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Filters'),
      -400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(_transaction.merchantName!),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('+36 pts'), findsOneWidget);
    expect(find.text('+17 pts'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Filters'),
      -400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(_travelTransaction.merchantName!),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(_travelTransaction.merchantName!), findsOneWidget);
    expect(find.text('+36 pts'), findsOneWidget);
    expect(find.text('+17 pts'), findsNothing);
  });

  testWidgets('rewards use points rather than currency labels', (tester) async {
    await pumpLedger(tester, width: 768);

    expect(find.text('36 pts'), findsOneWidget);
    expect(find.textContaining('₹36'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Details'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('+36 pts'), findsOneWidget);
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
