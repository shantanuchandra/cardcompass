import 'dart:io';
import 'dart:typed_data';
import 'package:cardcompass/core/services/pdf_parsing_service_impl.dart';
import 'package:cardcompass/core/services/transaction_parsing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Debug SBI transaction extraction step by step', () async {
    // Load the SBI PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/9391656461119329_08062025_SBI.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    // First extract text to see the format
    final rawText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your SBI Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'SBI',
      userName: 'shantanuchandra',
      onManualPasswordRequired: () async {
        return '021219905529';
      },
    );

    // Filter out everything after "Schedule of Charges"
    final scheduleIndex = rawText.toLowerCase().indexOf('schedule of charges');
    final extractedText = scheduleIndex != -1 
        ? rawText.substring(0, scheduleIndex) 
        : rawText;

    print('=== SBI FILTERED TEXT (length: ${extractedText.length}, filtered at: ${scheduleIndex != -1 ? 'Schedule of Charges' : 'Not found'}) ===');
    
    // Split into lines for analysis
    final lines = extractedText.split('\n');
    print('Total lines: ${lines.length}');
    
    // Find the transaction section
    int transactionStart = -1;
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('transactions for')) {
        transactionStart = i;
        print('TRANSACTIONS FOR found at line ${i + 1}: "${lines[i]}"');
        break;
      }
    }
    
    if (transactionStart != -1) {
      print('\n=== TRANSACTION SECTION (starting from line $transactionStart) ===');
      for (int i = transactionStart; i < transactionStart + 20 && i < lines.length; i++) {
        print('Line $i: "${lines[i]}"');
      }
      
      // Test the multi-line extraction
      print('\n=== TESTING MULTI-LINE EXTRACTION ===');
      final testLines = lines.sublist(transactionStart, transactionStart + 20);
      final sbiTransactions = TransactionParsingService.extractSBIMultiLineTransactions(testLines);
      print('SBI Multi-line transactions found: ${sbiTransactions.length}');
      
      for (final transaction in sbiTransactions) {
        print('- ${transaction['date']} | ${transaction['description']} | ₹${transaction['amount']} | ${transaction['type']}');
      }
      
      // Test the main extraction service
      print('\n=== TESTING MAIN EXTRACTION SERVICE ===');
      final allTransactions = TransactionParsingService.extractTransactionsFromText(
        text: extractedText,
        bankName: 'sbi',
      );
      
      print('Total transactions extracted: ${allTransactions.length}');
      for (final transaction in allTransactions) {
        print('- ${transaction['date']} | ${transaction['description']} | ₹${transaction['amount']} | ${transaction['type']}');
      }
    } else {
      print('❌ Transaction section not found');
      
      // Look for date patterns
      print('\n=== LOOKING FOR DATE PATTERNS ===');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (RegExp(r'\d{1,2}\s+\w{3}\s+\d{2}').hasMatch(line)) {
          print('Date pattern found at line $i: "$line"');
          if (i < lines.length - 3) {
            print('  Next lines:');
            print('    Line ${i+1}: "${lines[i+1]}"');
            print('    Line ${i+2}: "${lines[i+2]}"');
            print('    Line ${i+3}: "${lines[i+3]}"');
          }
        }
      }
    }
  });
}
