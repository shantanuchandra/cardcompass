import 'dart:typed_data';

abstract class PdfService {
  /// Parse credit card statement PDF file
  Future<Map<String, dynamic>> parseStatement(String filePath);

  /// Parse credit card statement from PDF bytes
  Future<Map<String, dynamic>> parseStatementFromBytes(Uint8List pdfBytes);

  /// Extract transactions from statement PDF
  Future<List<Map<String, dynamic>>> extractTransactions(String filePath);

  /// Extract statement metadata (date, amount, etc.)
  Future<Map<String, dynamic>> extractStatementMetadata(String filePath);

  /// Validate if PDF is a valid credit card statement
  Future<bool> isValidStatement(String filePath);

  /// Get supported banks for PDF parsing
  List<String> getSupportedBanks();

  /// Extract text from PDF
  Future<String> extractText(String filePath);

  /// Extract specific fields based on bank template
  Future<Map<String, dynamic>> extractFieldsByBank({
    required String filePath,
    required String bankName,
  });
}
