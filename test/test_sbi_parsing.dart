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

  test('Parse SBI statement and check amounts', () async {
    // Load the SBI PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/9391656461119329_08062025_SBI.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    // First extract text to see the format
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your SBI Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'SBI',
      userName: 'shantanuchandra',
      onManualPasswordRequired: () async {
        // Try common passwords for SBI statements
        return '021219905529';
      },
    );

    print('=== SBI EXTRACTED TEXT ===');
    print(extractedText); // Show full text instead of truncating
    print('=== END TEXT ===');

    // Parse the statement
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'SBI',
      emailSubject: 'Your SBI Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      userName: 'shantanuchandra',
      onManualPasswordRequired: () async {
        return 'SHAN0212';
      },
    );

    // Print the amounts
    print('\n=== PARSED TRANSACTIONS ===');
    for (final transaction in transactions) {
      print('Amount: ${transaction.amount}, Description: ${transaction.description}');
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
