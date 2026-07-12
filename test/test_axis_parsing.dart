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

  test('Parse Axis Vistara statement and check amounts', () async {
    // Load the Axis Vistara PDF file
    final file = File('assets/Credit Card Statement_AxisVistara.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    // First try without password (some PDFs might not be encrypted)
    final extractedText = await parsingService.extractTextFromPdfBytes(pdfBytes);

    print('=== AXIS VISTARA EXTRACTED TEXT ===');
    print(extractedText.substring(0, extractedText.length > 2000 ? 2000 : extractedText.length));
    print('=== END TEXT ===');

    // Parse the statement
    final transactions = await parsingService.parseStatement(
      pdfBytes: pdfBytes,
      bankName: 'Axis',
    );

    // Print the amounts
    print('\n=== PARSED TRANSACTIONS ===');
    for (final transaction in transactions) {
      print('Amount: ${transaction['amount']}, Description: ${transaction['description']}');
    }

    // For now, just check that text was extracted
    expect(extractedText.isNotEmpty, isTrue);
    
    // If transactions were found, test their amounts
    if (transactions.isNotEmpty) {
      expect(transactions.first['amount'], isA<num>());
      for (final transaction in transactions) {
        if (transaction['amount'] != null) {
          expect(transaction['amount'], greaterThan(0.0));
        }
      }
    }
  });
}
