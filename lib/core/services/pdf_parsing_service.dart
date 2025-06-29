import 'dart:typed_data';

/// Service interface for PDF parsing operations
abstract class PdfParsingService {
  /// Parse PDF statement and extract transactions (web-compatible)
  Future<List<Map<String, dynamic>>> parseStatement({
    required Uint8List pdfBytes,
    required String bankName,
    String? fileName,
  });

  /// Extract text from PDF bytes (web-compatible)
  Future<String> extractTextFromPdfBytes(Uint8List bytes);

  /// Validate PDF format from bytes (web-compatible)
  Future<bool> validatePdfFormatFromBytes(Uint8List bytes);

  /// Get supported banks for parsing
  List<String> getSupportedBanks();

  /// Parse HDFC Bank statement
  Future<List<Map<String, dynamic>>> parseHdfcStatement(String text);

  /// Parse SBI Card statement
  Future<List<Map<String, dynamic>>> parseSbiStatement(String text);

  /// Parse Axis Bank statement
  Future<List<Map<String, dynamic>>> parseAxisStatement(String text);

  /// Parse ICICI Bank statement
  Future<List<Map<String, dynamic>>> parseIciciStatement(String text);

  /// Parse generic statement format
  Future<List<Map<String, dynamic>>> parseGenericStatement(String text);
  /// Extract transaction data using AI-powered parsing and regex patterns
  Future<List<Map<String, dynamic>>> extractTransactionData({
    required String text,
    required List<RegExp> patterns,
  });

  /// Clean and normalize transaction data
  Map<String, dynamic> normalizeTransactionData(Map<String, dynamic> rawData);

  /// Convert amount string to double
  double parseAmount(String amountStr);

  /// Parse date string to DateTime
  DateTime parseDate(String dateStr);
}
