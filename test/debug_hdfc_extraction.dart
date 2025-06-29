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

  test('Debug HDFC text extraction and parsing', () async {
    // Load the HDFC DCB PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/3610XXXXXXXX81_15-06-2025_HDFC_DCB.PDF');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    print('=== DEBUGGING HDFC EXTRACTION ===');
    
    // Extract text with password detection and filtering
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

    print('Extracted text length: ${extractedText.length}');
    print('\n=== FULL EXTRACTED TEXT ===');
    print(extractedText);
    print('\n=== END OF EXTRACTED TEXT ===');
    
    // Check for specific patterns in the text
    final lines = extractedText.split('\n');
    print('\n=== ANALYZING LINES ===');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        print('Line $i: "$line"');
        
        // Look for date patterns
        if (RegExp(r'\d{2}/\d{2}/\d{4}').hasMatch(line)) {
          print('  -> Contains date pattern');
        }
        
        // Look for amount patterns
        if (RegExp(r'[\d,]+\.\d{2}').hasMatch(line)) {
          print('  -> Contains amount pattern');
        }
        
        // Look for transaction table headers
        if (line.toLowerCase().contains('domestic transaction') || 
            line.toLowerCase().contains('transaction description') ||
            line.toLowerCase().contains('amount') ||
            line.toLowerCase().contains('feature reward')) {
          print('  -> Transaction table related');
        }
      }
    }

    expect(extractedText.isNotEmpty, isTrue);
  });
}
