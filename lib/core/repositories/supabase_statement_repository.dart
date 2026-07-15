import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/core/repositories/statement_repository.dart';
import 'package:cardcompass/shared/models/statement.dart';

typedef StatementUpsert = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> statement, {
  required String onConflict,
});

typedef StatementPaymentRpc = Future<Map<String, dynamic>> Function(
  String functionName, {
  required Map<String, dynamic> params,
});

typedef ExistingStatementLookup = Future<Map<String, dynamic>?> Function({
  required String userId,
  required String userCardId,
  required dynamic statementDate,
});

/// Supabase implementation of the StatementRepository interface
/// Updated to fix UUID generation issue
class SupabaseStatementRepository implements StatementRepository {
  SupabaseStatementRepository({
    Future<String> Function(String userCardId)? resolveCatalogCardId,
    StatementUpsert? upsertStatement,
    StatementPaymentRpc? statementPaymentRpc,
    ExistingStatementLookup? findExistingStatement,
  })  : _resolveCatalogCardId =
            resolveCatalogCardId ?? _defaultResolveCatalogCardId,
        _upsertStatementOverride = upsertStatement,
        _statementPaymentRpcOverride = statementPaymentRpc,
        _findExistingStatement = findExistingStatement ??
            (upsertStatement != null
                ? _noExistingStatement
                : _defaultFindExistingStatement);

  // `late` so constructing this repository in a unit test that injects
  // [_resolveCatalogCardId] and never touches Supabase-backed methods doesn't
  // require Supabase.initialize() to have run first.
  late final SupabaseClient _supabase = Supabase.instance.client;

  /// Test seam: resolves a `user_cards.id` to its `catalog_card_id`. Defaults
  /// to the real Supabase lookup in production.
  final Future<String> Function(String userCardId) _resolveCatalogCardId;
  final StatementUpsert? _upsertStatementOverride;
  final StatementPaymentRpc? _statementPaymentRpcOverride;
  final ExistingStatementLookup _findExistingStatement;

  Future<Map<String, dynamic>> _upsertStatement(
    Map<String, dynamic> statement, {
    required String onConflict,
  }) async {
    final override = _upsertStatementOverride;
    if (override != null) {
      return override(statement, onConflict: onConflict);
    }

    return await _supabase
        .from('statements')
        .upsert(statement, onConflict: onConflict)
        .select()
        .single();
  }

  Future<Map<String, dynamic>> _statementPaymentRpc(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    final override = _statementPaymentRpcOverride;
    if (override != null) return override(functionName, params: params);
    final response = await _supabase.rpc(functionName, params: params);
    return Map<String, dynamic>.from(response as Map);
  }

  static Future<String> _defaultResolveCatalogCardId(String userCardId) async {
    final cardResponse = await Supabase.instance.client
        .from('user_cards')
        .select('catalog_card_id')
        .eq('id', userCardId)
        .single();
    return cardResponse['catalog_card_id'] as String;
  }

  static Future<Map<String, dynamic>?> _defaultFindExistingStatement({
    required String userId,
    required String userCardId,
    required dynamic statementDate,
  }) async {
    final response = await Supabase.instance.client
        .from('statements')
        .select('payment_status, paid_amount, paid_at, metadata')
        .eq('user_id', userId)
        .eq('user_card_id', userCardId)
        .eq('statement_date', statementDate)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  static Future<Map<String, dynamic>?> _noExistingStatement({
    required String userId,
    required String userCardId,
    required dynamic statementDate,
  }) async =>
      null;

  /// Columns backing the `statements` table's unique constraint
  /// (`statements_user_card_statement_date_key`, see
  /// supabase/migrations/20260714020000_enforce_user_card_ownership.sql).
  /// Must always match that constraint's columns exactly, or every
  /// statement upsert fails silently (caught and logged in
  /// DataPipelineDebugService, never surfaced to the user).
  static const String statementUpsertConflictColumns =
      'user_card_id,statement_date';

  @override
  Future<List<Statement>> getOpenStatementsForCard({
    required String userId,
    required String userCardId,
  }) async {
    final response = await _supabase
        .from('statements')
        .select('*')
        .eq('user_id', userId)
        .eq('user_card_id', userCardId)
        .inFilter('payment_status',
            const ['pending', 'partial', 'overdue']).order('due_date');
    return List<Map<String, dynamic>>.from(response)
        .map(Statement.fromJson)
        .toList();
  }

  @override
  Future<PaymentReconciliationResult> reconcileImportedPayment({
    required String sourceStatementId,
    required String userId,
    required String userCardId,
    required double paymentCredit,
    required List<PaymentUpdate> updates,
    required double unmatchedPaymentCredit,
  }) async {
    final response = await _statementPaymentRpc(
      'reconcile_imported_statement_payment',
      params: {
        'p_source_statement_id': sourceStatementId,
        'p_user_id': userId,
        'p_user_card_id': userCardId,
        'p_expected_payment_credit': paymentCredit,
      },
    );
    final rpcUpdates = (response['updates'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .map((value) => PaymentUpdate(
              value['statement_id'] as String,
              (value['payment_amount'] as num).toDouble(),
              PaymentStatus.values.firstWhere(
                (status) => status.name == value['payment_status'],
              ),
            ))
        .toList();
    return PaymentReconciliationResult(
      alreadyApplied: response['already_applied'] as bool? ?? false,
      appliedUpdates: rpcUpdates,
      unmatchedPaymentCredit:
          (response['unmatched_payment_credit'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> applyPaymentToStatement({
    required String statementId,
    required String userId,
    required String userCardId,
    required double paymentAmount,
    required PaymentStatus paymentStatus,
  }) async {
    await _statementPaymentRpc('apply_statement_payment', params: {
      'p_statement_id': statementId,
      'p_user_id': userId,
      'p_user_card_id': userCardId,
      'p_payment_amount': paymentAmount,
      'p_mark_paid': false,
    });
  }

  @override
  Future<void> markStatementPaid({
    required String statementId,
    required String userId,
    required String userCardId,
  }) async {
    await _statementPaymentRpc('apply_statement_payment', params: {
      'p_statement_id': statementId,
      'p_user_id': userId,
      'p_user_card_id': userCardId,
      'p_payment_amount': 0,
      'p_mark_paid': true,
    });
  }

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
      // cardId here is the owned user_cards.id; resolve its catalog card_id
      // so the required (NOT NULL) card_id column is populated correctly.
      final cardResponse = await _supabase
          .from('user_cards')
          .select('catalog_card_id')
          .eq('id', cardId)
          .single();
      final catalogCardId = cardResponse['catalog_card_id'] as String;

      // Upload file to Supabase Storage
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final filePath = 'statements/$userId/$fileName';

      await _supabase.storage.from('documents').upload(filePath, file);

      // Get the public URL
      final publicUrl = _supabase.storage
          .from('documents')
          .getPublicUrl(filePath); // Create statement record
      final result = await _supabase
          .from('statements')
          .insert({
            // Let Supabase auto-generate UUID for 'id' field
            'user_id': userId,
            'card_id': catalogCardId,
            'user_card_id': cardId,
            'file_path': publicUrl,
            'file_name': fileName,
            'processed': false,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

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
    throw UnimplementedError(
        'Statement parsing not implemented in repository. Use PdfParsingService directly.');
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
      await _supabase.from('statements').delete().eq('id', statementId);
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
      print(
          '🔍 SupabaseStatementRepository: Fetching statements for user: $userId');

      final response = await _supabase
          .from('statements')
          .select('*')
          .eq('user_id', userId)
          .order('statement_date', ascending: false);

      print('📋 SupabaseStatementRepository: Raw response: $response');

      final statements = List<Map<String, dynamic>>.from(response)
          .map((data) => Statement.fromJson(data))
          .toList();

      print(
          '📋 SupabaseStatementRepository: Parsed ${statements.length} statements');

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

      // Resolve card_id (catalog_card_id) from user_cards table. userCardId
      // must reference a real user_cards row — silently falling back to
      // userCardId itself here previously wrote a user_cards.id into the
      // card_id column (which actually references card_catalog(id)),
      // corrupting the row instead of surfacing the real problem.
      final catalogCardId = await _resolveCatalogCardId(userCardId);

      final statementMap = {
        'user_id': userId,
        'card_id': catalogCardId, // References card_catalog(id)
        'user_card_id': userCardId, // References user_cards(id)
        'statement_date':
            statementData['statement_date'] ?? now.toIso8601String(),
        'due_date': statementData['due_date'] ??
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'total_amount': statementData['total_amount'] ?? 0.0,
        'minimum_payment': statementData['min_amount_due'] ??
            statementData['minimum_payment'] ??
            0.0,
        'closing_balance': statementData['previous_balance'] ??
            statementData['closing_balance'] ??
            0.0,
        'available_credit': statementData['available_credit'] ?? 0.0,
        'interest_charged': statementData['interest_charged'] ?? 0.0,
        'fees_charged': statementData['fees_charged'] ?? 0.0,
        'payment_status': 'pending',
        'rewards_earned': statementData['rewards_earned'] ?? 0,
        'file_path': filePath ?? statementData['file_path'],
        'file_name': statementData['file_name'] ??
            filePath?.split('/').last ??
            'statement.pdf',
        'metadata': statementData['metadata'] ?? {},
        'processed': true,
        'transaction_count':
            (statementData['transactions'] as List?)?.length ?? 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      // Supabase upsert overwrites each submitted field on conflict. Preserve
      // fields owned by payment reconciliation when this is a reimport.
      final existing = await _findExistingStatement(
        userId: userId,
        userCardId: userCardId,
        statementDate: statementMap['statement_date'],
      );
      if (existing != null) {
        _preserveReconciliationState(statementMap, existing);
      }

      // Upsert on (user_card_id, statement_date) so re-syncing the same
      // statement period is idempotent and returns the existing row instead of 409.
      final result = await _upsertStatement(
        statementMap,
        onConflict: statementUpsertConflictColumns,
      );

      return Statement.fromJson(result);
    } catch (e) {
      throw Exception('Failed to create statement: $e');
    }
  }

  static void _preserveReconciliationState(
    Map<String, dynamic> incoming,
    Map<String, dynamic> existing,
  ) {
    for (final field in const ['payment_status', 'paid_amount', 'paid_at']) {
      if (existing.containsKey(field) && existing[field] != null) {
        incoming[field] = existing[field];
      }
    }

    final existingMetadata = Map<String, dynamic>.from(
      existing['metadata'] as Map? ?? const <String, dynamic>{},
    );
    final incomingMetadata = Map<String, dynamic>.from(
      incoming['metadata'] as Map? ?? const <String, dynamic>{},
    );
    for (final key in const [
      'payment_reconciliation_state',
      'unmatched_payment_credit',
    ]) {
      if (existingMetadata.containsKey(key)) {
        incomingMetadata[key] = existingMetadata[key];
      }
    }
    incoming['metadata'] = incomingMetadata;
  }
}
