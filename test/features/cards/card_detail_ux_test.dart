import 'dart:async';

import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/cards/screens/card_detail_screen.dart';
import 'package:cardcompass/features/cards/domain/card_statement_archive.dart';
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

final _previousStatement = Statement(
  id: 'statement-july',
  userId: 'user-1',
  cardId: 'catalog-1',
  userCardId: 'card-1',
  statementDate: DateTime(2026, 7, 5),
  dueDate: DateTime(2026, 7, 22),
  totalAmount: 7000,
  paymentStatus: PaymentStatus.paid,
  paidAmount: 7000,
  createdAt: DateTime(2026, 7, 5),
);

Future<void> pumpDetail(
  WidgetTester tester, {
  double textScale = 1,
  Statement? statement,
  List<Transaction> transactions = const [],
  double currentMonthSpend = 0,
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
        cardMonthSpendProvider(
          'card-1',
        ).overrideWith((ref) async => currentMonthSpend),
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
  testWidgets('statement chips switch the bill and exact transaction set', (
    tester,
  ) async {
    final augustTransaction = Transaction(
      id: 'august-transaction',
      userId: 'user-1',
      userCardId: 'card-1',
      amount: 490,
      description: 'August merchant',
      transactionType: TransactionType.debit,
      transactionDate: DateTime(2026, 8, 11),
      statementId: 'statement-1',
      createdAt: DateTime(2026, 8, 11),
    );
    final julyTransaction = Transaction(
      id: 'july-transaction',
      userId: 'user-1',
      userCardId: 'card-1',
      amount: 7000,
      description: 'July merchant',
      transactionType: TransactionType.debit,
      transactionDate: DateTime(2026, 7, 3),
      statementId: 'statement-july',
      createdAt: DateTime(2026, 7, 3),
    );
    final unbilled = Transaction(
      id: 'unbilled',
      userId: 'user-1',
      userCardId: 'card-1',
      amount: 250,
      description: 'Unbilled merchant',
      transactionType: TransactionType.debit,
      transactionDate: DateTime(2026, 8, 16),
      createdAt: DateTime(2026, 8, 16),
    );
    final archive = CardStatementArchive(
      statements: [_previousStatement, _statement],
      transactions: [julyTransaction, unbilled, augustTransaction],
    );

    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          cardDetailProvider('card-1').overrideWith((ref) async => _card),
          cardStatementArchiveProvider(
            'card-1',
          ).overrideWith((ref) async => archive),
          cardMonthSpendProvider('card-1').overrideWith((ref) async => 490),
        ],
        child: MaterialApp(
          theme: AppTheme.work,
          home: const CardDetailScreen(cardId: 'card-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Statement transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Aug ’26'), findsOneWidget);
    expect(find.text('Jul ’26'), findsOneWidget);
    expect(find.text('August merchant'), findsOneWidget);
    expect(find.text('July merchant'), findsNothing);
    expect(find.text('Unbilled merchant'), findsOneWidget);

    await tester.tap(find.text('Jul ’26'));
    await tester.pumpAndSettle();

    expect(find.text('July merchant'), findsOneWidget);
    expect(find.text('August merchant'), findsNothing);
    expect(find.text('Paid'), findsWidgets);
  });

  testWidgets('detail puts decisions before disclosures', (tester) async {
    await pumpDetail(tester);

    final headings = [
      'Card summary',
      'Best uses',
      'Milestone',
      'Current bill',
      'History',
      'Rewards & fees',
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

  testWidgets(
    'a statement balance with no current-month purchases explains the mismatch',
    (tester) async {
      await pumpDetail(tester, statement: _statement, currentMonthSpend: 0);

      await tester.ensureVisible(find.text('Current bill'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No purchases are recorded this month'),
        findsOneWidget,
      );
      expect(find.textContaining('not yet imported'), findsOneWidget);
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

  testWidgets('detail loading reserves space and a missing card offers exit', (
    tester,
  ) async {
    final pending = Completer<UserCard?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          cardDetailProvider('missing').overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(
          theme: AppTheme.work,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CardDetailScreen(cardId: 'missing'),
                    ),
                  ),
                  child: const Text('Open missing card'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open missing card'));
    await tester.pumpAndSettle();

    final loading = find.byKey(const Key('card-detail-loading'));
    expect(loading, findsOneWidget);
    expect(tester.getSize(loading).height, greaterThanOrEqualTo(240));

    pending.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Card not found'), findsOneWidget);
    expect(find.text('Back to cards'), findsOneWidget);
    await tester.tap(find.text('Back to cards'));
    await tester.pumpAndSettle();
    expect(find.text('Open missing card'), findsOneWidget);
  });
}
