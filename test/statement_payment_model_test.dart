import 'package:cardcompass/shared/models/statement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
