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

  test('Debug HDFC transaction extraction', () async {
    final file = File('d:/CC/CC_all/cardcompass/assets/3610XXXXXXXX81_15-06-2025_DCB.PDF');
    final Uint8List pdfBytes = await file.readAsBytes();
    final parsingService = PdfParsingServiceImpl();

    print('=== DEBUGGING HDFC DCB STATEMENT ===');
    
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your HDFC Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'HDFC',
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

    print('\n=== EXTRACTED TEXT ANALYSIS ===');
    final lines = extractedText.split('\n');
    print('Total lines: ${lines.length}');
    
    // Look for transaction-related content
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && 
          (line.toLowerCase().contains('transaction') || 
           line.toLowerCase().contains('amount') ||
           line.toLowerCase().contains('date') ||
           RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(line) ||
           RegExp(r'[\d,]+\.\d{2}').hasMatch(line))) {
        print('Line $i: "$line"');
      }
    }

    // Look for lines around transaction section
    print('\n=== LINES AROUND TRANSACTION SECTION (60-90) ===');
    for (int i = 60; i < 90 && i < lines.length; i++) {
      print('Line $i: "${lines[i]}"');
    }
    
    // Look for patterns that look like transactions
    print('\n=== POTENTIAL TRANSACTION PATTERNS ===');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && 
          (RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(line) ||
           RegExp(r'[\d,]+\.\d{2}').hasMatch(line))) {
        // Show this line and next few lines for context
        print('Pattern Line $i: "$line"');
        if (i + 1 < lines.length) print('  Next: "${lines[i + 1]}"');
        if (i + 2 < lines.length) print('  Next+1: "${lines[i + 2]}"');
      }
    }
  });

  test('Debug IndusInd transaction extraction', () async {
    final file = File('d:/CC/CC_all/cardcompass/assets/CC_STMT_075992154_527254_0605202505062025_IndusInd.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();
    final parsingService = PdfParsingServiceImpl();

    print('\n=== DEBUGGING INDUSIND STATEMENT ===');
    
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your IndusInd Bank Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'IndusInd',
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
        return 'shan0212';
      },
    );

    print('\n=== EXTRACTED TEXT ANALYSIS ===');
    final lines = extractedText.split('\n');
    print('Total lines: ${lines.length}');
    
    // Look specifically at lines around the transaction section that was detected
    print('\n=== LINES AROUND DETECTED TRANSACTION SECTION (lines 80-100) ===');
    for (int i = 80; i < 100 && i < lines.length; i++) {
      print('Line $i: "${lines[i]}"');
    }
    
    // Look for actual transaction patterns
    print('\n=== SEARCHING FOR TRANSACTION PATTERNS ===');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty && 
          (RegExp(r'\d{2}\/\d{2}\/\d{4}').hasMatch(line) ||
           RegExp(r'[\d,]+\.\d{2}\s*(DR|CR|Dr|Cr)?').hasMatch(line) ||
           line.toLowerCase().contains('eazydiner') ||
           line.toLowerCase().contains('restaurant'))) {
        print('Pattern Line $i: "$line"');
      }
    }
  });
}
