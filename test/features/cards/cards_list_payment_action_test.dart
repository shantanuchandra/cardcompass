import 'package:cardcompass/features/cards/models/card_statement_summary.dart';
import 'package:cardcompass/features/cards/presentation/screens/cards_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final unpaidSummary = CardStatementSummary(
    statementId: 'statement-1',
    userCardId: 'card-1',
    statementDate: DateTime(2026, 7, 1),
    dueDate: DateTime(2026, 7, 25),
    totalAmount: 1000,
    paidAmount: 100,
  );

  testWidgets('marks only the selected card statement paid after confirmation',
      (tester) async {
    final paidStatementIds = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: unpaidSummary,
          onMarkPaid: () async =>
              paidStatementIds.add(unpaidSummary.statementId),
        ),
      ),
    ));

    await tester.tap(find.text('MARK PAID'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Travel Card'), findsOneWidget);
    await tester.tap(find.text('CONFIRM PAYMENT').last);
    await tester.pumpAndSettle();

    expect(paidStatementIds, ['statement-1']);
  });

  testWidgets('does not mark a statement paid when confirmation is cancelled',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: unpaidSummary,
          onMarkPaid: () async => calls++,
        ),
      ),
    ));

    await tester.tap(find.text('MARK PAID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(calls, 0);
  });

  testWidgets('does not offer payment for a paid statement', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: unpaidSummary.copyWith(
              paidAmount: 1000, paidAt: DateTime(2026, 7, 2)),
          onMarkPaid: () async {},
        ),
      ),
    ));

    expect(find.text('MARK PAID'), findsNothing);
    expect(find.textContaining('PAID'), findsOneWidget);
  });

  testWidgets('preserves paise in due, confirmation, and paid amounts',
      (tester) async {
    final fractionalSummary = unpaidSummary.copyWith(paidAmount: 99.50);
    final paidFractionalSummary = CardStatementSummary(
      statementId: 'statement-2',
      userCardId: 'card-1',
      statementDate: DateTime(2026, 7, 1),
      dueDate: DateTime(2026, 7, 25),
      totalAmount: 900.50,
      paidAmount: 900.50,
      paidAt: DateTime(2026, 7, 2),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: fractionalSummary,
          onMarkPaid: () async {},
        ),
      ),
    ));

    expect(find.text('AMOUNT DUE  ₹900.50'), findsOneWidget);
    expect(find.textContaining('₹901'), findsNothing);

    await tester.tap(find.text('MARK PAID'));
    await tester.pumpAndSettle();
    expect(find.text('Mark ₹900.50 paid for Travel Card?'), findsOneWidget);
    expect(find.textContaining('₹901'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: paidFractionalSummary,
          onMarkPaid: () async {},
        ),
      ),
    ));

    expect(find.text('PAID ₹900.50 · 02/07/2026'), findsOneWidget);
  });

  testWidgets(
      'shows an error and leaves the payment action available on failure',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: unpaidSummary,
          onMarkPaid: () async => throw Exception('repository failed'),
        ),
      ),
    ));

    await tester.tap(find.text('MARK PAID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM PAYMENT').last);
    await tester.pumpAndSettle();

    expect(find.text('Could not mark statement paid. Please try again.'),
        findsOneWidget);
    expect(find.text('MARK PAID'), findsOneWidget);
  });

  testWidgets('shows no statement available when a card has no statement',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: CardStatementPaymentPanel(
          cardName: 'Travel Card',
          summary: null,
          onMarkPaid: null,
        ),
      ),
    ));

    expect(find.text('No statement available'), findsOneWidget);
    expect(find.text('MARK PAID'), findsNothing);
  });
}
