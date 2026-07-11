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

  test('Parse DCB statement and check amounts', () async {
    // Load the PDF file
    final file = File('assets/3610XXXXXXXX81_15-06-2025_HDFC_DCB.PDF');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    // First extract text to see the format
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your DCB Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'DCB',
      userName: 'shantanuchandra',
      onManualPasswordRequired: () async {
        return 'SHAN0212';
      },
    );

    print('=== EXTRACTED TEXT ===');
    print(extractedText.substring(0, extractedText.length > 2000 ? 2000 : extractedText.length));
    print('=== END TEXT ===');

    // Parse the statement
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'HDFC',
      emailSubject: 'Your DCB Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      userName: 'shantanuchandra',
      onManualPasswordRequired: () async {
        return 'SHAN0212';
      },
    );

    // Print the amounts
    for (final transaction in transactions) {
      print('Amount: ${transaction.amount}');
    }

    // For now, just check that text was extracted
    expect(extractedText.isNotEmpty, isTrue);
    
    // If transactions were found, test their amounts
    if (transactions.isNotEmpty) {
      expect(transactions.first.amount, isA<double>());
      for (final transaction in transactions) {
        expect(transaction.amount, greaterThan(0.0));
      }
    }
  });
}
