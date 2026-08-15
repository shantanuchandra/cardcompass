import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/cards/screens/card_detail_screen.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/shared/models/transaction.dart';
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

final _statement = Statement(
  id: 'statement-1',
  userId: 'user-1',
  cardId: 'catalog-1',
  userCardId: 'card-1',
  statementDate: DateTime(2026, 8, 5),
  dueDate: DateTime(2026, 8, 22),
  totalAmount: 12000,
  minimumPayment: 1200,
  closingBalance: 12000,
  availableCredit: 238000,
  paymentStatus: PaymentStatus.pending,
  createdAt: DateTime(2026, 8, 5),
);

final _transaction = Transaction(
  id: 'transaction-1',
  userId: 'user-1',
  userCardId: 'card-1',
  amount: 1500,
  description:
      'Very long merchant name that must stay available to assistive technology',
  merchantName:
      'Very long merchant name that must stay available to assistive technology',
  category: 'Dining',
  transactionType: TransactionType.debit,
  transactionDate: DateTime(2026, 8, 15),
  createdAt: DateTime(2026, 8, 15),
);

Future<void> pumpDetail(
  WidgetTester tester, {
  double textScale = 1,
  Statement? statement,
  List<Transaction> transactions = const [],
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(null),
        cardDetailProvider('card-1').overrideWith((ref) async => _card),
        cardTransactionsProvider(
          'card-1',
        ).overrideWith((ref) async => transactions),
        cardStatementProvider('card-1').overrideWith((ref) async => statement),
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

    await tester.ensureVisible(find.text('Rewards & fees'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rewards & fees'));
    await tester.pumpAndSettle();
    expect(find.text('Annual fee'), findsOneWidget);
  });

  testWidgets('detail remains usable with long names at 200% scale', (
    tester,
  ) async {
    await pumpDetail(tester, textScale: 2);

    expect(find.text(_card.displayName), findsWidgets);
    final titleRect = tester.getRect(find.text(_card.displayName).last);
    expect(titleRect.left, greaterThanOrEqualTo(0));
    expect(titleRect.right, lessThanOrEqualTo(390));
    expect(
      tester.getSemantics(find.text(_card.displayName).last).label,
      contains(_card.displayName),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'summary action, bill, and history work at 390px and 200% scale',
    (tester) async {
      await pumpDetail(
        tester,
        textScale: 2,
        statement: _statement,
        transactions: [_transaction],
      );

      expect(
        find.bySemanticsLabel('Review transaction history'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('review-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Bill Due'), findsOneWidget);
      expect(find.text(_transaction.merchantName!), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('detail errors redact backend details and provide retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          cardDetailProvider('card-1').overrideWith(
            (ref) async => throw StateError('private statement join failure'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.work,
          home: const CardDetailScreen(cardId: 'card-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load this card.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private statement join failure'), findsNothing);
  });
}
