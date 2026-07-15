import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> statementJson({
    double totalAmount = 1000,
    dynamic paidAmount = 0,
    bool includePaidAmount = true,
  }) {
    return {
      'id': 'statement-1',
      'user_id': 'user-1',
      'user_card_id': 'card-1',
      'statement_date': '2026-07-01T00:00:00.000Z',
      'due_date': '2026-07-21T00:00:00.000Z',
      'minimum_payment': 0,
      'closing_balance': 0,
      'available_credit': 0,
      'rewards_earned': 0,
      'interest_charged': 0,
      'fees_charged': 0,
      'file_path': '',
      'file_name': '',
      'created_at': '2026-07-01T00:00:00.000Z',
      'total_amount': totalAmount,
      if (includePaidAmount) 'paid_amount': paidAmount,
      'payment_status': 'pending',
    };
  }

  Statement statement({double totalAmount = 1000, double paidAmount = 0}) {
    return Statement(
      id: 'statement-1',
      userId: 'user-1',
      userCardId: 'card-1',
      statementDate: DateTime.utc(2026, 7, 1),
      dueDate: DateTime.utc(2026, 7, 21),
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      minimumPayment: 0,
      closingBalance: 0,
      availableCredit: 0,
      rewardsEarned: 0,
      interestCharged: 0,
      feesCharged: 0,
      paymentStatus: PaymentStatus.pending,
      filePath: '',
      fileName: '',
      createdAt: DateTime.utc(2026, 7, 1),
    );
  }

  test('maps paid amount and derives amount still due', () {
    final statement = Statement.fromJson({
      'id': 'statement-1',
      'user_id': 'user-1',
      'user_card_id': 'card-1',
      'statement_date': '2026-07-01T00:00:00.000Z',
      'due_date': '2026-07-21T00:00:00.000Z',
      'minimum_payment': 0,
      'closing_balance': 0,
      'available_credit': 0,
      'rewards_earned': 0,
      'interest_charged': 0,
      'fees_charged': 0,
      'file_path': '',
      'file_name': '',
      'created_at': '2026-07-01T00:00:00.000Z',
      'total_amount': 1000,
      'paid_amount': 250,
      'paid_at': '2026-07-16T10:00:00.000Z',
      'payment_status': 'partial',
    });

    expect(statement.remainingAmount, 750);
    expect(statement.paidAt, DateTime.parse('2026-07-16T10:00:00.000Z'));
  });

  test('defaults a missing paid amount to zero', () {
    expect(
      Statement.fromJson(statementJson(includePaidAmount: false)).paidAmount,
      0,
    );
  });

  test('rejects negative paid amounts from every construction path', () {
    expect(() => statement(paidAmount: -1), throwsArgumentError);
    expect(
      () => Statement.fromJson(statementJson(paidAmount: -1)),
      throwsArgumentError,
    );
    expect(
      () => statement().copyWith(paidAmount: -1),
      throwsArgumentError,
    );
  });

  test('rejects paid amounts above the statement total', () {
    expect(
      () => Statement.fromJson(statementJson(paidAmount: 1000.01)),
      throwsArgumentError,
    );
  });

  test('rejects non-finite payment amounts', () {
    expect(
      () => Statement.fromJson(statementJson(paidAmount: double.nan)),
      throwsArgumentError,
    );
    expect(
      () => Statement.fromJson(statementJson(totalAmount: double.infinity)),
      throwsArgumentError,
    );
  });
}
