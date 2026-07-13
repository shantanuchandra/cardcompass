import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:cardcompass/core/services/error_handling_service.dart';
import 'package:cardcompass/core/services/pdf_parsing_service.dart';
import 'package:cardcompass/core/services/pdf_password_detection_service.dart';
import 'package:cardcompass/core/services/transaction_parsing_service.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'parsing_logger.dart';

/// Enhanced service for parsing credit card statements from PDF files
class PdfParsingServiceImpl implements PdfParsingService {
  final PdfPasswordDetectionService _passwordService = PdfPasswordDetectionService();
  
  @override
  Future<String> extractTextFromPdfBytes(Uint8List bytes) async {
    try {
      final document = PdfDocument(inputBytes: bytes);
      
      final textExtractor = PdfTextExtractor(document);
      final extractedText = textExtractor.extractText();
      
      document.dispose();
      return extractedText;
    } catch (error, stackTrace) {
      // Check if this is an encryption error
      if (error.toString().contains('password') ||
          error.toString().contains('encrypted') ||
          error.toString().contains('Cannot open an encrypted document')) {
        // This fallback path has no email/bank context, so password detection
        // can't be attempted here. The primary path (extractTextWithPasswordDetection)
        // already ran and failed — this means all password candidates were exhausted
        // or no manual password was provided.
        ParsingLogger.summary('❌ PDF is encrypted and all password candidates failed — returning empty text');
        print('❌ extractTextFromPdfBytes: encrypted PDF, password detection already exhausted in primary path');
        return '';
      }
      
      ErrorHandlingService.logError(
        'PDF Text Extraction',
        error,
        stackTrace: stackTrace,
        additionalData: {
          'fileSize': bytes.length,
        },
      );
      return '';
    }
  }

  /// Extract text from PDF with intelligent password detection
  Future<String> extractTextWithPasswordDetection({
    required Uint8List pdfBytes,
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    required String bankName,
    String? userName,
    Map<String, dynamic>? userProfile,
    String? fileName,
    Future<String?> Function()? onManualPasswordRequired,
  }) async {
    try {
      final extractedText = await _passwordService.findPasswordAndExtractText(
        pdfBytes: pdfBytes,
        emailSubject: emailSubject,
        emailBody: emailBody,
        userEmail: userEmail,
        bankName: bankName,
        userName: userName,
        userProfile: userProfile,
        fileName: fileName,
        onManualPasswordRequired: onManualPasswordRequired,
      );
      
      if (extractedText == null) return '';
      
      // For SBI, filter out everything after "Schedule of Charges"
      if (bankName.toLowerCase() == 'sbi') {
        final scheduleIndex = extractedText.toLowerCase().indexOf('schedule of charges');
        if (scheduleIndex != -1) {
          final filteredText = extractedText.substring(0, scheduleIndex);
          ParsingLogger.summary('SBI PDF: Filtered out content after "Schedule of Charges" (removed ${extractedText.length - filteredText.length} characters)');
          return filteredText;
        }
      }
      
      // For HDFC, filter out everything after "Important Information" but only if it comes after transaction data
      if (bankName.toLowerCase() == 'hdfc') {
        // First check if we have transaction data (look for "Domestic Transactions" section)
        final domesticTransIndex = extractedText.toLowerCase().indexOf('domestic transactions');
        final importantInfoIndex = extractedText.toLowerCase().indexOf('important information');
        
        if (importantInfoIndex != -1 && domesticTransIndex != -1 && importantInfoIndex > domesticTransIndex) {
          // Only filter if "Important Information" comes after "Domestic Transactions"
          final filteredText = extractedText.substring(0, importantInfoIndex);
          ParsingLogger.summary('HDFC PDF: Filtered out content after "Important Information" (removed ${extractedText.length - filteredText.length} characters)');
          return filteredText;
        } else if (importantInfoIndex != -1 && domesticTransIndex == -1) {
          // If no "Domestic Transactions" found but "Important Information" is there, might be cutting off too early
          ParsingLogger.warning('HDFC PDF: "Important Information" found but no "Domestic Transactions" section detected. Keeping full text.');
        }
      }
      
      return extractedText;
    } catch (error, stackTrace) {
      ErrorHandlingService.logError(
        'PDF Text Extraction with Password Detection',
        error,
        stackTrace: stackTrace,
        additionalData: {
          'fileSize': pdfBytes.length,
          'bankName': bankName,
        },
      );
      return '';
    }
  }

  /// Parse PDF statement from bytes and return transactions
  /// Web-compatible version that works without file system access
  Future<List<Transaction>> parseStatementPdf({
    required Uint8List pdfBytes,
    required String bankName,
    required String emailSubject,
    required String emailBody,
    required String userEmail,
    required String? userName,
    Map<String, dynamic>? userProfile,
    String? fileName,
    Future<String?> Function()? onManualPasswordRequired,
    bool minimizeDebugOutput = false,
  }) async {
    try {
      String text = '';
      
      // For credit card statements, try password detection first since they're typically encrypted
      text = await extractTextWithPasswordDetection(
        pdfBytes: pdfBytes,
        emailSubject: emailSubject,
        emailBody: emailBody,
        userEmail: userEmail,
        bankName: bankName,
        userName: userName,
        userProfile: userProfile,
        fileName: fileName,
        onManualPasswordRequired: onManualPasswordRequired,
      );
      
      // If password detection didn't work or wasn't available, try regular extraction
      if (text.isEmpty) {
        ParsingLogger.summary('Password: Candidate search failed, attempting regular PDF extraction...');
        text = await extractTextFromPdfBytes(pdfBytes);
      }

      // Parse statement using enhanced AI-powered transaction parsing
      List<Map<String, dynamic>> rawTransactions = [];
      switch (bankName.toLowerCase()) {
        case 'hdfc bank':
          rawTransactions = await parseHdfcStatement(text);
          break;
        case 'sbi card':
          rawTransactions = await parseSbiStatement(text);
          break;
        case 'axis bank':
          rawTransactions = await parseAxisStatement(text);
          break;
        case 'icici bank':
          rawTransactions = await parseIciciStatement(text);
          break;
        default:
          rawTransactions = await TransactionParsingService.extractTransactionsFromText(
            text: text,
            bankName: bankName,
          );
      }
      // final rawTransactions = await TransactionParsingService.extractTransactionsFromText(
      //   text: text,
      //   bankName: bankName,
      // );

      // Convert to Transaction objects
      final transactions = rawTransactions.map<Transaction>((data) {
        // Parse the date string to DateTime
        DateTime transactionDate;
        try {
          if (data['date'] is String) {
            final dateParts = (data['date'] as String).split('/');
            if (dateParts.length == 3) {
              transactionDate = DateTime(
                int.parse(dateParts[2]), // year
                int.parse(dateParts[1]), // month
                int.parse(dateParts[0]), // day
              );
            } else {
              transactionDate = DateTime.now();
            }
          } else {
            transactionDate = data['date'] ?? DateTime.now();
          }
        } catch (e) {
          transactionDate = DateTime.now();
        }

        return Transaction(
          id: data['id'] ?? '',
          userId: data['userId'] ?? '',
          userCardId: data['userCardId'] ?? '',
          amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
          description: data['description'] ?? '',
          merchantName: data['merchantName'],
          category: _parseCategory(data['category']),
          type: data['type'] == 'credit' ? TransactionType.credit : TransactionType.debit,
          transactionDate: transactionDate,
          createdAt: DateTime.now(),
        );
      }).toList();
      
      return transactions;
    } catch (error, stackTrace) {
      ErrorHandlingService.logError(
        'PDF Statement Parsing from Bytes',
        error,
        stackTrace: stackTrace,
        additionalData: {
          'bankName': bankName,
          'bytesLength': pdfBytes.length,
        },
      );
      return [];
    }
  }

  /// Parse category string to TransactionCategory enum
  TransactionCategory _parseCategory(String? category) {
    if (category == null) return TransactionCategory.other;
    
    switch (category.toUpperCase()) {
      case 'FOOD_DINING':
      case 'FOOD':
        return TransactionCategory.food;
      case 'TRANSPORTATION':
      case 'TRANSPORT':
        return TransactionCategory.transport;
      case 'SHOPPING':
        return TransactionCategory.shopping;
      case 'FUEL':
        return TransactionCategory.fuel;
      case 'HEALTHCARE':
      case 'MEDICAL':
        return TransactionCategory.medical;
      case 'ENTERTAINMENT':
        return TransactionCategory.entertainment;
      case 'GROCERY':
        return TransactionCategory.grocery;
      case 'UTILITIES':
        return TransactionCategory.utilities;
      case 'TRAVEL':
        return TransactionCategory.travel;
      default:
        return TransactionCategory.other;
    }
  }

  // Placeholder implementations for interface compliance
  @override
  Future<List<Map<String, dynamic>>> parseStatement({
    required Uint8List pdfBytes,
    required String bankName,
    String? fileName,
  }) async {
    throw UnimplementedError('Use parseStatementPdf instead');
  }

  @override
  Future<bool> validatePdfFormatFromBytes(Uint8List bytes) async {
    try {
      if (bytes.length < 4) return false;
      final signature = String.fromCharCodes(bytes.take(4));
      if (signature != '%PDF') return false;
      final document = PdfDocument(inputBytes: bytes);
      document.dispose();
      return true;
    } catch (error) {
      return false;
    }
  }

  @override
  List<String> getSupportedBanks() {
    return ['HDFC Bank', 'SBI Card', 'Axis Bank', 'ICICI Bank'];
  }

  @override
  Future<List<Map<String, dynamic>>> parseHdfcStatement(String text) async {
    final transactions = <Map<String, dynamic>>[];
    final regex = RegExp(r'(\d{2}\/\d{2}\/\d{4})\s+([A-Za-z0-9\s\.\-&*@#]+?)\s+([\d,]+\.\d{2})\s*(Cr|Dr)?');
    final matches = regex.allMatches(text);
    for (final match in matches) {
      final date = match.group(1);
      final description = match.group(2);
      final amountStr = match.group(3);
      final type = match.group(4);
      if (date != null && description != null && amountStr != null) {
        final amount = double.tryParse(amountStr.replaceAll(',', ''));
        if (amount != null) {
          transactions.add({
            'date': date,
            'description': description.trim(),
            'amount': amount * (type?.toLowerCase() == 'dr' ? -1 : 1),
          });
        }
      }
    }
    return transactions;
  }

  @override
  Future<List<Map<String, dynamic>>> parseSbiStatement(String text) async {
    return TransactionParsingService.extractSBIMultiLineTransactions(text.split('\n'));
  }

  @override
  Future<List<Map<String, dynamic>>> parseAxisStatement(String text) async {
    return TransactionParsingService.extractAxisMultiLineTransactions(text.split('\n'));
  }

  @override
  Future<List<Map<String, dynamic>>> parseIciciStatement(String text) async {
    return TransactionParsingService.extractICICITransactions(text.split('\n'));
  }

  @override
  Future<List<Map<String, dynamic>>> parseGenericStatement(String text) async {
    throw UnimplementedError('Use parseStatementPdf instead');
  }

  @override
  Future<List<Map<String, dynamic>>> extractTransactionData({
    required String text,
    required List<RegExp> patterns,
  }) async {
    throw UnimplementedError('Use parseStatementPdf instead');
  }

  @override
  Map<String, dynamic> normalizeTransactionData(Map<String, dynamic> rawData) {
    throw UnimplementedError('Use parseStatementPdf instead');
  }

  @override
  double parseAmount(String amountStr) {
    throw UnimplementedError('Use parseStatementPdf instead');
  }

  @override
  DateTime parseDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[2]), // year
          int.parse(parts[1]), // month
          int.parse(parts[0]), // day
        );
      }
      return DateTime.now();
    } catch (e) {
      return DateTime.now();
    }
  }
}

