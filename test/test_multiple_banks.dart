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

  test('Test HDFC DCB statement parsing', () async {
    // Load the HDFC DCB PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/3610XXXXXXXX81_15-06-2025_HDFC_DCB.PDF');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    print('=== TESTING HDFC DCB STATEMENT ===');
    
    // Extract text with password detection
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

    // Parse the statement using the main parsing service
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

    print('\n=== HDFC DCB TRANSACTIONS ===');
    print('Total transactions found: ${transactions.length}');
    
    for (final transaction in transactions) {
      print('Date: ${transaction.transactionDate}');
      print('Description: ${transaction.description}');
      print('Amount: ₹${transaction.amount}');
      print('Type: ${transaction.type}');
      print('Category: ${transaction.category}');
      print('---');
    }

    // Validate results
    expect(extractedText.isNotEmpty, isTrue);
    if (transactions.isNotEmpty) {
      expect(transactions.first.amount, isA<double>());
      for (final transaction in transactions) {
        expect(transaction.amount, greaterThan(0.0));
        expect(transaction.description.isNotEmpty, isTrue);
      }
    }
  });

  test('Test Axis Vistara statement parsing', () async {
    // Load the Axis Vistara PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/Credit Card Statement_AxisVistara.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    print('\n=== TESTING AXIS VISTARA STATEMENT ===');
    
    // Extract text with password detection
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your Axis Bank Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'AXIS',
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
        return 'shan0212';  // Use the lowercase version with date
      },
    );

    print('Extracted text length: ${extractedText.length}');

    // Parse the statement using the main parsing service
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'AXIS',
      emailSubject: 'Your Axis Bank Credit Card Statement',
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
        return 'shan0212';  // Use the lowercase version with date
      },
    );

    print('\n=== AXIS VISTARA TRANSACTIONS ===');
    print('Total transactions found: ${transactions.length}');
    
    for (final transaction in transactions) {
      print('Date: ${transaction.transactionDate}');
      print('Description: ${transaction.description}');
      print('Amount: ₹${transaction.amount}');
      print('Type: ${transaction.type}');
      print('Category: ${transaction.category}');
      print('---');
    }

    // Validate results
    expect(extractedText.isNotEmpty, isTrue);
    if (transactions.isNotEmpty) {
      expect(transactions.first.amount, isA<double>());
      for (final transaction in transactions) {
        expect(transaction.amount, greaterThan(0.0));
        expect(transaction.description.isNotEmpty, isTrue);
      }
    }
  });

  test('Test IndusInd statement parsing', () async {
    // Load the IndusInd PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/CC_STMT_075992154_527254_0605202505062025_IndusInd.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    print('\n=== TESTING INDUSIND STATEMENT ===');
    
    // Extract text with password detection
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
        return 'shan0212';  // Use the lowercase version with date
      },
    );

    print('Extracted text length: ${extractedText.length}');

    // Parse the statement using the main parsing service
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'IndusInd',
      emailSubject: 'Your IndusInd Bank Credit Card Statement',
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
        return 'shan0212';  // Use the lowercase version with date
      },
    );

    print('\n=== INDUSIND TRANSACTIONS ===');
    print('Total transactions found: ${transactions.length}');
    
    for (final transaction in transactions) {
      print('Date: ${transaction.transactionDate}');
      print('Description: ${transaction.description}');
      print('Amount: ₹${transaction.amount}');
      print('Type: ${transaction.type}');
      print('Category: ${transaction.category}');
      print('---');
    }

    // Validate results
    expect(extractedText.isNotEmpty, isTrue);
    if (transactions.isNotEmpty) {
      expect(transactions.first.amount, isA<double>());
      for (final transaction in transactions) {
        expect(transaction.amount, greaterThan(0.0));
        expect(transaction.description.isNotEmpty, isTrue);
      }
    }
  });

  test('Test SBI statement parsing', () async {
    // Load the SBI PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/9391656461119329_08062025_SBI.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    print('\n=== TESTING SBI STATEMENT ===');
    
    // Extract text with password detection
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your SBI Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'SBI',
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
        return '021219905529';  // SBI specific password
      },
    );

    print('Extracted text length: ${extractedText.length}');

    // Parse the statement using the main parsing service
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'SBI',
      emailSubject: 'Your SBI Credit Card Statement',
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
        return '021219905529';  // SBI specific password
      },
    );

    print('\n=== SBI TRANSACTIONS ===');
    print('Total transactions found: ${transactions.length}');
    
    for (final transaction in transactions) {
      print('Date: ${transaction.transactionDate}');
      print('Description: ${transaction.description}');
      print('Amount: ₹${transaction.amount}');
      print('Type: ${transaction.type}');
      print('Category: ${transaction.category}');
      print('---');
    }

    // Validate results
    expect(extractedText.isNotEmpty, isTrue);
    if (transactions.isNotEmpty) {
      expect(transactions.first.amount, isA<double>());
      for (final transaction in transactions) {
        expect(transaction.amount, greaterThan(0.0));
        expect(transaction.description.isNotEmpty, isTrue);
      }
    }
  });

  test('Test HSBC statement parsing', () async {
    // Load the HSBC PDF file
    final file = File('d:/CC/CC_all/cardcompass/assets/20250605_HSBC.pdf');
    final Uint8List pdfBytes = await file.readAsBytes();

    // Create an instance of the parsing service
    final parsingService = PdfParsingServiceImpl();

    print('\n=== TESTING HSBC STATEMENT ===');
    
    // Extract text with password detection
    final extractedText = await parsingService.extractTextWithPasswordDetection(
      pdfBytes: pdfBytes,
      emailSubject: 'Your HSBC Credit Card Statement',
      emailBody: 'Please find attached your credit card statement.',
      userEmail: 'shantanu.msp@gmail.com',
      bankName: 'HSBC',
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
        return '021290683285';  // HSBC specific password
      },
    );

    print('Extracted text length: ${extractedText.length}');

    // Parse the statement using the main parsing service
    final transactions = await parsingService.parseStatementPdf(
      pdfBytes: pdfBytes,
      bankName: 'HSBC',
      emailSubject: 'Your HSBC Credit Card Statement',
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
        return '021290683285';  // HSBC specific password
      },
    );

    print('\n=== HSBC TRANSACTIONS ===');
    print('Total transactions found: ${transactions.length}');
    
    for (final transaction in transactions) {
      print('Date: ${transaction.transactionDate}');
      print('Description: ${transaction.description}');
      print('Amount: ₹${transaction.amount}');
      print('Type: ${transaction.type}');
      print('Category: ${transaction.category}');
      print('---');
    }

    // Validate results
    expect(extractedText.isNotEmpty, isTrue);
    if (transactions.isNotEmpty) {
      expect(transactions.first.amount, isA<double>());
      for (final transaction in transactions) {
        expect(transaction.amount, greaterThan(0.0));
        expect(transaction.description.isNotEmpty, isTrue);
      }
    }
  });
}
