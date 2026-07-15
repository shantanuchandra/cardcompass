import 'package:cardcompass/features/cards/models/card_statement_summary.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Statement statement({
    required String id,
    required String cardId,
    required DateTime statementDate,
    required DateTime dueDate,
    double totalAmount = 1000,
    double paidAmount = 0,
    PaymentStatus paymentStatus = PaymentStatus.pending,
    DateTime? paidAt,
  }) =>
      Statement(
        id: id,
        userId: 'user-1',
        userCardId: cardId,
        statementDate: statementDate,
        dueDate: dueDate,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        paidAt: paidAt,
        minimumPayment: 100,
        closingBalance: totalAmount,
        availableCredit: 0,
        rewardsEarned: 0,
        interestCharged: 0,
        feesCharged: 0,
        paymentStatus: paymentStatus,
        filePath: '',
        fileName: 'statement.pdf',
        createdAt: statementDate,
      );

  test('selects the latest statement per owned card', () {
    final oldStatement = statement(
      id: 'old',
      cardId: 'card-a',
      statementDate: DateTime(2026, 6, 1),
      dueDate: DateTime(2026, 6, 25),
    );
    final latestStatement = statement(
      id: 'latest',
      cardId: 'card-a',
      statementDate: DateTime(2026, 7, 1),
      dueDate: DateTime(2026, 7, 25),
      totalAmount: 1000,
      paidAmount: 100,
    );

    final summaries =
        buildCardStatementSummaries([oldStatement, latestStatement]);

    expect(summaries['card-a']!.dueDate, DateTime(2026, 7, 25));
    expect(summaries['card-a']!.remainingAmount, 900);
  });

  test('retains paid amount and date for a paid latest statement', () {
    final paidAt = DateTime(2026, 7, 4);
    final summaries = buildCardStatementSummaries([
      statement(
        id: 'paid',
        cardId: 'card-a',
        statementDate: DateTime(2026, 7, 1),
        dueDate: DateTime(2026, 7, 25),
        paidAmount: 1000,
        paymentStatus: PaymentStatus.paid,
        paidAt: paidAt,
      ),
    ]);

    expect(summaries['card-a']!.remainingAmount, 0);
    expect(summaries['card-a']!.paidAt, paidAt);
    expect(summaries['card-a']!.isPaid, isTrue);
  });
}
