import 'package:cardcompass/core/services/statement_processing_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts HSBC primary card last-four from a masked PDF line', () {
    expect(
      extractPrimaryCardLastFour(
        'Primary card number\n51xx xxxx xxxx 1759\nStatement date 15 July',
      ),
      '1759',
    );
  });

  test('extracts HSBC last-four when the PDF text layer fragments digits', () {
    expect(
      extractPrimaryCardLastFour(
        'Primary card number\n5 1 x x   x x x x   x x x x   1 7 5 9',
      ),
      '1759',
    );
  });

  test('keeps a valid parsed last-four ahead of PDF fallback evidence', () {
    expect(
      statementInfoWithCardLastFour(const {
        'card_last4': '4321',
      }, 'Primary card number 51xx xxxx xxxx 1759')['card_last4'],
      '4321',
    );
  });

  test('card identity hints retain only safe resolution evidence', () {
    final hints = buildCardIdentityHints(
      bankName: 'HDFC Bank',
      attachmentFilename: 'statement-aug.pdf',
      statementInfo: const {
        'card_last4': ' 4821 ',
        'card_name': ' Regalia Gold ',
        'statement_date': '2026-08-12',
        'due_date': '2026-09-02',
        'total_amount': 18420.50,
        'transactions': ['must not be copied'],
      },
    );

    expect(hints, {
      'bank': 'HDFC Bank',
      'last4': '4821',
      'productName': 'Regalia Gold',
      'statementDate': '2026-08-12',
      'dueDate': '2026-09-02',
      'totalAmount': 18420.50,
      'attachmentFilename': 'statement-aug.pdf',
    });
  });

  test('card identity hints omit blank and malformed values', () {
    final hints = buildCardIdentityHints(
      bankName: 'ICICI Bank',
      attachmentFilename: ' ',
      statementInfo: const {
        'card_last4': '82',
        'card_name': ' ',
        'statement_date': null,
        'total_amount': 'unknown',
      },
    );

    expect(hints, {'bank': 'ICICI Bank'});
  });

  test('confirmed assignment clears only the pending decision flag', () {
    expect(
      metadataAfterCardAssignment(const {
        'needsCardAssignment': true,
        'attachmentId': 'attachment-1',
        'identityHints': {'last4': '4821'},
      }),
      const {
        'attachmentId': 'attachment-1',
        'identityHints': {'last4': '4821'},
      },
    );
  });
}
