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

  group('All Bank PDF Parsing Tests', () {
    
    test('Parse SBI statement', () async {
      final file = File('assets/9391656461119329_08062025_SBI.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'SBI',
        emailSubject: 'Your SBI Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return '021219905529';
        },
      );

      print('🏦 SBI Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse HDFC DCB statement', () async {
      final file = File('assets/3610XXXXXXXX81_15-06-2025_HDFC_DCB.PDF');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'HDFC',
        emailSubject: 'Your HDFC DCB Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'SHAN0212';
        },
      );

      print('🏦 HDFC DCB Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse HDFC Swiggy statement', () async {
      final file = File('assets/5268XXXXXXXXXX01_15-06-2025_HDFC_Swiggy.PDF');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'HDFC',
        emailSubject: 'Your HDFC Swiggy Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'SHAN0212';
        },
      );

      print('🏦 HDFC Swiggy Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse HDFC Tata Neu Infinity statement', () async {
      final file = File('assets/6529XXXXXXXXXX11_01-06-2025_HDFC_TataNeuInfinity.PDF');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'HDFC',
        emailSubject: 'Your HDFC Tata Neu Infinity Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'SHAN0212';
        },
      );

      print('🏦 HDFC Tata Neu Infinity Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse IndusInd statement', () async {
      final file = File('assets/CC_STMT_075992154_527254_0605202505062025_IndusInd.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'IndusInd',
        emailSubject: 'Your IndusInd Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'shan0212';
        },
      );

      print('🏦 IndusInd Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse ICICI Sapphiro statement', () async {
      final file = File('assets/3769XXXXXXXX3003_777450_ICICI_Sapphiro_NORM.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'ICICI',
        emailSubject: 'Your ICICI Sapphiro Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'shan0212';
        },
      );

      print('🏦 ICICI Sapphiro Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse ICICI Amazon statement', () async {
      final file = File('assets/4315XXXXXXXX6006_1343157_ICICI_Amazon_NORM.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'ICICI',
        emailSubject: 'Your ICICI Amazon Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'shan0212';
        },
      );

      print('🏦 ICICI Amazon Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse Axis Vistara statement', () async {
      final file = File('assets/Credit Card Statement_AxisVistara.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'Axis',
        emailSubject: 'Your Axis Vistara Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'SHAN0212';
        },
      );

      print('🏦 Axis Vistara Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse HSBC statement', () async {
      final file = File('assets/20250605_HSBC.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'HSBC',
        emailSubject: 'Your HSBC Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return '021290683285';
        },
      );

      print('🏦 HSBC Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse PNB statement', () async {
      final file = File('assets/2231832797_PNB.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'PNB',
        emailSubject: 'Your PNB Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'shan02121990';
        },
      );

      print('🏦 PNB Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse IDFC PowerPlus statement', () async {
      final file = File('assets/90300002407570_20062025_132200376_IDFC_PowerPlus.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'IDFC',
        emailSubject: 'Your IDFC PowerPlus Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return '0212';
        },
      );

      print('🏦 IDFC PowerPlus Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });

    test('Parse Zenith statement', () async {
      final file = File('assets/0001694019044117488_ZENITH_21002159_Jun-25.pdf');
      final Uint8List pdfBytes = await file.readAsBytes();
      final parsingService = PdfParsingServiceImpl();

      final transactions = await parsingService.parseStatementPdf(
        pdfBytes: pdfBytes,
        bankName: 'Zenith',
        emailSubject: 'Your Zenith Credit Card Statement',
        emailBody: 'Please find attached your credit card statement.',
        userEmail: 'shantanu.msp@gmail.com',
        userName: 'shantanuchandra',
        onManualPasswordRequired: () async {
          return 'SHAN0212';
        },
      );

      print('🏦 Zenith Statement - Transactions found: ${transactions.length}');
      for (final transaction in transactions.take(5)) {
        print('  ${transaction.transactionDate.toString().split(' ')[0]} | ${transaction.description} | ₹${transaction.amount}');
      }

      expect(transactions, isA<List>());
      if (transactions.isNotEmpty) {
        expect(transactions.first.amount, greaterThan(0.0));
      }
    });
  });
}
