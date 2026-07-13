import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';

void main() {
  group('PdfParsingServiceImpl bank-name trailer filters', () {
    test('filters HDFC trailer using the real bank name string ("HDFC Bank"), not just "hdfc"', () {
      // _getBankNameFromSender in enhanced_gmail_service.dart returns 'HDFC Bank',
      // never the bare 'hdfc' string the original guard compared against.
      const text = '''
HDFC BANK REGALIA CREDIT CARD
Domestic Transactions:
16 May 26  ZOMATO ORDER            520.00
18 May 26  FLIPKART INTERNET      8499.00

Important Information
Please verify transactions on statement within 30 days.
Grievance Cell: HDFC Bank Cards Division, Chennai - 600002.
''';

      final result = PdfParsingServiceImpl.filterHdfcTrailer(text, 'HDFC Bank');

      expect(result, contains('ZOMATO ORDER'));
      expect(result, isNot(contains('Grievance Cell')),
          reason: 'Trailer after "Important Information" (which follows "Domestic Transactions") should be filtered for the real bank-name string used in production');
    });

    test('keeps full text when "Domestic Transactions" is absent, to avoid cutting off too early', () {
      const text = '''
HDFC BANK CREDIT CARD STATEMENT

Important Information
Please verify transactions on statement within 30 days.
16 May 26  ZOMATO ORDER            520.00
''';

      final result = PdfParsingServiceImpl.filterHdfcTrailer(text, 'HDFC Bank');

      expect(result, contains('ZOMATO ORDER'),
          reason: 'Without a confirmed "Domestic Transactions" anchor, filtering must back off to avoid dropping real transactions');
    });

    test('filters SBI trailer using the real bank name string ("SBI Card"), not just "sbi"', () {
      // _getBankNameFromSender returns 'SBI Card', never the bare 'sbi' string
      // the original guard compared against.
      const text = '''
SBI CARD BPCL MONTHLY STATEMENT
05 Jul 26  SWIGGY BANGALORE         450.00 D

Schedule of Charges
Annual fee: Rs. 500 + GST
''';

      final result = PdfParsingServiceImpl.filterSbiTrailer(text, 'SBI Card');

      expect(result, contains('SWIGGY BANGALORE'));
      expect(result, isNot(contains('Annual fee')));
    });
  });
}
