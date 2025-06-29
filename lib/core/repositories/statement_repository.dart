import 'dart:io';
import 'package:cardcompass/shared/models/statement.dart';

/// Repository interface for statement operations
abstract class StatementRepository {
  /// Get user's statements
  Future<List<Map<String, dynamic>>> getUserStatements(String userId);

  /// Get user's statements as Statement objects
  Future<List<Statement>> getStatements(String userId);

  /// Create a new statement
  Future<Statement> createStatement({
    required String userId,
    required String userCardId,
    required Map<String, dynamic> statementData,
    String? filePath,
    String? emailId,
  });

  /// Upload and process a statement file
  Future<String> uploadStatement({
    required String userId,
    required String cardId,
    required File file,
  });

  /// Parse statement and extract transactions
  Future<List<Map<String, dynamic>>> parseStatement({
    required String userId,
    required String cardId,
    required String filePath,
  });

  /// Get statement by ID
  Future<Map<String, dynamic>?> getStatementById(String statementId);

  /// Update statement processing status
  Future<void> updateStatementStatus({
    required String statementId,
    required bool processed,
  });

  /// Delete a statement
  Future<void> deleteStatement(String statementId);

  /// Get statements for a specific card
  Future<List<Map<String, dynamic>>> getStatementsForCard({
    required String userId,
    required String cardId,
  });

  /// Import statements from Gmail
  Future<List<Map<String, dynamic>>> importFromGmail(String userId);

  /// Check if file is a valid statement
  Future<bool> validateStatementFile(File file);

  /// Get supported file formats
  List<String> getSupportedFormats();
}
