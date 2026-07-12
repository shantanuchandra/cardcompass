import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/shared/models/statement.dart';

/// Supabase implementation of the StatementRepository interface
/// Updated to fix UUID generation issue
class SupabaseStatementRepository implements StatementRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  Future<List<Map<String, dynamic>>> getUserStatements(String userId) async {
    try {
      final response = await _supabase
          .from('statements')
          .select('*')
          .eq('user_id', userId)
          .order('statement_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch user statements: $e');
    }
  }

  @override
  Future<String> uploadStatement({
    required String userId,
    required String cardId,
    required File file,
  }) async {
    try {
      // Upload file to Supabase Storage
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final filePath = 'statements/$userId/$fileName';

      await _supabase.storage
          .from('documents')
          .upload(filePath, file);

      // Get the public URL
      final publicUrl = _supabase.storage
          .from('documents')
          .getPublicUrl(filePath);      // Create statement record
      final result = await _supabase.from('statements').insert({
        // Let Supabase auto-generate UUID for 'id' field
        'user_id': userId,
        'user_card_id': cardId,
        'file_path': publicUrl,
        'file_name': fileName,
        'processed': false,
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      return result['id'] as String;
    } catch (e) {
      throw Exception('Failed to upload statement: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> parseStatement({
    required String userId,
    required String cardId,
    required String filePath,
  }) async {
    // Parsing of statements via PDF should be handled by PdfParsingService
    throw UnimplementedError('Statement parsing not implemented in repository. Use PdfParsingService directly.');
  }

  @override
  Future<Map<String, dynamic>?> getStatementById(String statementId) async {
    try {
      final response = await _supabase
          .from('statements')
          .select('*')
          .eq('id', statementId)
          .single();

      return response;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> updateStatementStatus({
    required String statementId,
    required bool processed,
  }) async {
    try {
      await _supabase.from('statements').update({
        'processed': processed,
        'processed_at': processed ? DateTime.now().toIso8601String() : null,
      }).eq('id', statementId);
    } catch (e) {
      throw Exception('Failed to update statement status: $e');
    }
  }

  @override
  Future<void> deleteStatement(String statementId) async {
    try {
      await _supabase
          .from('statements')
          .delete()
          .eq('id', statementId);
    } catch (e) {
      throw Exception('Failed to delete statement: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getStatementsForCard({
    required String userId,
    required String cardId,
  }) async {
    try {
      final response = await _supabase
          .from('statements')
          .select('*')
          .eq('user_id', userId)
          .eq('card_id', cardId)
          .order('statement_date', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to fetch statements for card: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> importFromGmail(String userId) async {
    try {
      // TODO: Implement Gmail integration
      // This would involve:
      // 1. Connecting to Gmail API
      // 2. Searching for statement emails
      // 3. Downloading PDF attachments
      // 4. Processing them through parseStatement
      
      // For now, return empty list
      return [];
    } catch (e) {
      throw Exception('Failed to import from Gmail: $e');
    }
  }

  @override
  Future<bool> validateStatementFile(File file) async {
    try {
      // Check file extension
      final fileName = file.path.toLowerCase();
      if (!fileName.endsWith('.pdf')) {
        return false;
      }

      // Check file size (max 10MB)
      final fileSize = await file.length();
      if (fileSize > 10 * 1024 * 1024) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  List<String> getSupportedFormats() {
    return ['pdf'];
  }
  @override
  Future<List<Statement>> getStatements(String userId) async {
    try {
      print('🔍 SupabaseStatementRepository: Fetching statements for user: $userId');
      
      final response = await _supabase
          .from('statements')
          .select('*')
          .eq('user_id', userId)
          .order('statement_date', ascending: false);

      print('📋 SupabaseStatementRepository: Raw response: $response');
      
      final statements = List<Map<String, dynamic>>.from(response)
          .map((data) => Statement.fromJson(data))
          .toList();
          
      print('📋 SupabaseStatementRepository: Parsed ${statements.length} statements');
      
      return statements;
    } catch (e) {
      print('❌ SupabaseStatementRepository: Error fetching statements: $e');
      throw Exception('Failed to fetch statements: $e');
    }
  }

  @override
  Future<Statement> createStatement({
    required String userId,
    required String userCardId,
    required Map<String, dynamic> statementData,
    String? filePath,
    String? emailId,
  }) async {
    try {
      final now = DateTime.now();
      
      // Resolve card_id (catalog_card_id) from user_cards table
      String catalogCardId = userCardId;
      try {
        final cardResponse = await _supabase
            .from('user_cards')
            .select('card_id')
            .eq('id', userCardId)
            .single();
        catalogCardId = cardResponse['card_id'] as String;
      } catch (e) {
        print('⚠️ Could not resolve catalog card_id for userCardId $userCardId: $e');
      }

      final statementMap = {
        'user_id': userId,
        'card_id': catalogCardId, // References card_catalog(id)
        'user_card_id': userCardId, // References user_cards(id)
        'statement_date': statementData['statement_date'] ?? now.toIso8601String(),
        'due_date': statementData['due_date'] ?? DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'total_amount': statementData['total_amount'] ?? 0.0,
        'minimum_payment': statementData['min_amount_due'] ?? statementData['minimum_payment'] ?? 0.0,
        'closing_balance': statementData['previous_balance'] ?? statementData['closing_balance'] ?? 0.0,
        'available_credit': statementData['available_credit'] ?? 0.0,
        'interest_charged': statementData['interest_charged'] ?? 0.0,
        'fees_charged': statementData['fees_charged'] ?? 0.0,
        'payment_status': 'pending',
        'rewards_earned': statementData['rewards_earned'] ?? 0,
        'file_path': filePath ?? statementData['file_path'],
        'file_name': statementData['file_name'] ?? filePath?.split('/').last ?? 'statement.pdf',
        'processed': true,
        'transaction_count': (statementData['transactions'] as List?)?.length ?? 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      // Upsert on (card_id, statement_date) so re-syncing the same
      // statement period is idempotent and returns the existing row instead of 409.
      final result = await _supabase
          .from('statements')
          .upsert(statementMap, onConflict: 'card_id,statement_date')
          .select()
          .single();

      return Statement.fromJson(result);
    } catch (e) {
      throw Exception('Failed to create statement: $e');
    }
  }
}
