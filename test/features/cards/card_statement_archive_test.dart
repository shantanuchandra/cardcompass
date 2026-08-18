import 'package:cardcompass/features/cards/domain/card_statement_archive.dart';
import 'package:cardcompass/shared/models/statement.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

Statement statement(String id, DateTime date) => Statement(
  id: id,
  userId: 'user-1',
  cardId: 'catalog-1',
  userCardId: 'card-1',
  statementDate: date,
  dueDate: date.add(const Duration(days: 20)),
  totalAmount: 1000,
  paymentStatus: PaymentStatus.pending,
  createdAt: date,
);

Transaction transaction({
  required String id,
  required DateTime date,
  String? statementId,
}) => Transaction(
  id: id,
  userId: 'user-1',
  userCardId: 'card-1',
  amount: 100,
  description: id,
  transactionType: TransactionType.debit,
  transactionDate: date,
  statementId: statementId,
  createdAt: date,
);

void main() {
  test('remaining amount never becomes negative after an overpayment', () {
    final overpaid = Statement(
      id: 'overpaid',
      userId: 'user-1',
      cardId: 'catalog-1',
      userCardId: 'card-1',
      statementDate: DateTime(2026, 8, 15),
      dueDate: DateTime(2026, 9, 4),
      totalAmount: 1000,
      paidAmount: 1200,
      paymentStatus: PaymentStatus.paid,
      createdAt: DateTime(2026, 8, 15),
    );

    expect(overpaid.outstanding, 0);
  });

  test('latest statement is selected regardless of repository row order', () {
    final archive = CardStatementArchive(
      statements: [
        statement('july', DateTime(2026, 7, 15)),
        statement('august', DateTime(2026, 8, 15)),
      ],
      transactions: const [],
    );

    expect(archive.latestStatement?.id, 'august');
    expect(archive.statements.map((item) => item.id), ['august', 'july']);
  });

  test('statement membership uses statement id instead of date inference', () {
    final archive = CardStatementArchive(
      statements: [statement('august', DateTime(2026, 8, 15))],
      transactions: [
        transaction(
          id: 'belongs-to-august-despite-july-date',
          date: DateTime(2026, 7, 31),
          statementId: 'august',
        ),
        transaction(
          id: 'same-date-different-statement',
          date: DateTime(2026, 7, 31),
          statementId: 'july',
        ),
      ],
    );

    expect(archive.transactionsFor('august').map((item) => item.id), [
      'belongs-to-august-despite-july-date',
    ]);
  });

  test(
    'unbilled activity is null-statement activity after the latest close',
    () {
      final archive = CardStatementArchive(
        statements: [statement('august', DateTime(2026, 8, 15))],
        transactions: [
          transaction(id: 'unbilled', date: DateTime(2026, 8, 16)),
          transaction(id: 'old-unassigned', date: DateTime(2026, 8, 14)),
          transaction(
            id: 'already-billed',
            date: DateTime(2026, 8, 16),
            statementId: 'august',
          ),
        ],
      );

      expect(archive.unbilledTransactions.map((item) => item.id), ['unbilled']);
    },
  );
}
