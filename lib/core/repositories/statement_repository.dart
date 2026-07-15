import 'dart:io';
import 'package:cardcompass/shared/models/statement.dart';

/// A single allocation from an imported statement payment credit.
class PaymentUpdate {
  const PaymentUpdate(this.statementId, this.paymentAmount, this.paymentStatus);

  final String statementId;
  final double paymentAmount;
  final PaymentStatus paymentStatus;

  @override
  bool operator ==(Object other) =>
      other is PaymentUpdate &&
      other.statementId == statementId &&
      other.paymentAmount == paymentAmount &&
      other.paymentStatus == paymentStatus;

  @override
  int get hashCode => Object.hash(statementId, paymentAmount, paymentStatus);
}

/// Result returned after atomically reconciling one imported payment credit.
class PaymentReconciliationResult {
  const PaymentReconciliationResult({
    this.alreadyApplied = false,
    this.appliedUpdates = const [],
    this.unmatchedPaymentCredit = 0,
  });

  final bool alreadyApplied;
  final List<PaymentUpdate> appliedUpdates;
  final double unmatchedPaymentCredit;
}

/// Repository interface for statement operations
abstract class StatementRepository {
  /// Fetch unpaid statements owned by [userId] for one owned card.
  Future<List<Statement>> getOpenStatementsForCard({
    required String userId,
    required String userCardId,
  });

  /// Atomically reconcile one imported statement payment credit.
  ///
  /// Implementations must treat [sourceStatementId] as an idempotency key and
  /// must independently verify the source's parsed payment amount.
  Future<PaymentReconciliationResult> reconcileImportedPayment({
    required String sourceStatementId,
    required String userId,
    required String userCardId,
    required double paymentCredit,
    required List<PaymentUpdate> updates,
    required double unmatchedPaymentCredit,
  });

  /// Apply one payment amount to a user-owned statement.
  Future<void> applyPaymentToStatement({
    required String statementId,
    required String userId,
    required String userCardId,
    required double paymentAmount,
    required PaymentStatus paymentStatus,
  });

  /// Mark a user-owned statement paid using exactly its remaining balance.
  Future<void> markStatementPaid({
    required String statementId,
    required String userId,
    required String userCardId,
  });

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
