import 'dart:io';
import 'dart:typed_data';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Test HDFC DCB transaction extraction only', () async {
    final file = File('d:/CC/CC_all/cardcompass/assets/3610XXXXXXXX81_15-06-2025_HDFC_DCB.PDF');
    final Uint8List pdfBytes = await file.readAsBytes();
    final parsingService = PdfParsingServiceImpl();

    print('=== TESTING HDFC DCB PARSING ===');
    
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'HDFC',
      emailSubject: 'Your HDFC Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      userName: 'shantanu',
      userProfile: {
        'firstName': 'shantanu',
        'birthday': {
          'day': '02',
          'month': '12',
          'year': '1990',
          'ddmmyyyy': '02121990',
          'yyyymmdd': '19901202',
          'ddmmyy': '021290',
          'ddmm': '0212',
          'mmddyyyy': '12021990',
          'yymmdd': '901202',
        }
      },
      onManualPasswordRequired: () async {
        return 'SHAN0212';
      },
    );

    print('\n=== FINAL RESULTS ===');
    print('Total transactions found: ${transactions.length}');
    
    for (final transaction in transactions) {
      print('Date: ${transaction.transactionDate}');
      print('Description: ${transaction.description}');
      print('Amount: ₹${transaction.amount}');
      print('Type: ${transaction.type}');
      print('---');
    }

    expect(transactions.length, greaterThan(0), reason: 'Should find at least one transaction');
  });
}
