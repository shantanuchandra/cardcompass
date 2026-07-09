import 'dart:io';
import 'package:cardcompass/core/mock/mock_data.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/shared/models/statement.dart';

class MockStatementRepository implements StatementRepository {
  final List<Statement> _statements = MockData.statements();

  @override
  Future<List<Map<String, dynamic>>> getUserStatements(String userId) async {
    return _statements.map((s) => s.toJson()).toList();
  }

  @override
  Future<List<Statement>> getStatements(String userId) async => List.unmodifiable(_statements);

  @override
  Future<Statement> createStatement({
    required String userId,
    required String userCardId,
    required Map<String, dynamic> statementData,
    String? filePath,
    String? emailId,
  }) async {
    final statement = Statement.fromJson({
      'id': 'mock-stmt-${_statements.length + 1}',
      'user_id': userId,
      'user_card_id': userCardId,
      'statement_date': DateTime.now().toIso8601String(),
      'due_date': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
      'total_amount': statementData['total_amount'] ?? 0,
      'minimum_payment': statementData['minimum_payment'] ?? 0,
      'closing_balance': statementData['closing_balance'] ?? 0,
      'available_credit': statementData['available_credit'] ?? 0,
      'rewards_earned': statementData['rewards_earned'] ?? 0,
      'interest_charged': statementData['interest_charged'] ?? 0,
      'fees_charged': statementData['fees_charged'] ?? 0,
      'payment_status': 'pending',
      'file_path': filePath ?? '',
      'file_name': statementData['file_name'] ?? 'statement.pdf',
      'created_at': DateTime.now().toIso8601String(),
    });
    _statements.add(statement);
    return statement;
  }

  @override
  Future<String> uploadStatement({required String userId, required String cardId, required File file}) async {
    return 'mock-upload-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<Map<String, dynamic>>> parseStatement({
    required String userId,
    required String cardId,
    required String filePath,
  }) async {
    return [];
  }

  @override
  Future<Map<String, dynamic>?> getStatementById(String statementId) async {
    final matches = _statements.where((s) => s.id == statementId);
    return matches.isEmpty ? null : matches.first.toJson();
  }

  @override
  Future<void> updateStatementStatus({required String statementId, required bool processed}) async {
    final index = _statements.indexWhere((s) => s.id == statementId);
    if (index != -1) _statements[index] = _statements[index].copyWith();
  }

  @override
  Future<void> deleteStatement(String statementId) async {
    _statements.removeWhere((s) => s.id == statementId);
  }

  @override
  Future<List<Map<String, dynamic>>> getStatementsForCard({required String userId, required String cardId}) async {
    return _statements.where((s) => s.userCardId == cardId).map((s) => s.toJson()).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> importFromGmail(String userId) async => [];

  @override
  Future<bool> validateStatementFile(File file) async => file.existsSync();

  @override
  List<String> getSupportedFormats() => ['pdf'];
}
