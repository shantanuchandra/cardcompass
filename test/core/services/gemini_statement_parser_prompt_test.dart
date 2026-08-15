import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/gemini_statement_parser.dart';

void main() {
  group('buildTransactionsPrompt', () {
    final prompt = buildTransactionsPrompt(bankName: 'HDFC Bank');

    test('contains the corrected 16-category vocabulary', () {
      expect(prompt, contains('food|fuel|grocery|entertainment|travel|shopping|'
          'utilities|insurance|medical|education|investment|transport|'
          'rental|subscription|gift|other'));
    });

    test('does not contain any of the old, wrong vocabulary values as '
        'category options (bills/transfer/fee/payment/cash/dining)', () {
      // These words might legitimately appear elsewhere in the prompt (e.g.
      // "payment" in general instructional text), so check the specific
      // category-vocabulary line doesn't contain the old pipe-delimited list.
      expect(prompt, isNot(contains('shopping|dining|travel|fuel|entertainment|'
          'bills|transfer|fee|payment|cash|other')));
    });

    test('instructs Gemini to report the observed currency, not assume '
        'INR as the sole example', () {
      expect(prompt, contains('actual currency'));
      expect(prompt, isNot(contains('"currency": "INR"')));
    });

    test('interpolates bankName into both the intro sentence (uppercased) '
        'and the BANK: label (as-given)', () {
      expect(prompt, contains('HDFC BANK')); // intro sentence, .toUpperCase()
      expect(prompt, contains('BANK: HDFC Bank')); // label line, raw
    });
  });
}
