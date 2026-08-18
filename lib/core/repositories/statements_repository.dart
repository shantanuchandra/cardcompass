import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/statement.dart';

class StatementsRepository {
  final SupabaseClient _db;
  StatementsRepository(this._db);

  Future<List<Statement>> getUserStatements(
    String userId, {
    int limit = 20,
  }) async {
    final data = await _db
        .from('statements')
        .select()
        .eq('user_id', userId)
        .order('statement_date', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => Statement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Statement>> getStatementsForCard({
    required String userId,
    required String userCardId,
  }) async {
    final data = await _db
        .from('statements')
        .select()
        .eq('user_id', userId)
        .eq('user_card_id', userCardId)
        .order('statement_date', ascending: false);
    return (data as List)
        .map((row) => Statement.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  // Latest statement per card — used for the bill panel on the dashboard
  Future<Map<String, Statement>> getLatestStatementPerCard(
    String userId,
  ) async {
    final stmts = await getUserStatements(userId, limit: 100);
    final map = <String, Statement>{};
    for (final s in stmts) {
      if (!map.containsKey(s.userCardId)) {
        map[s.userCardId] = s;
      }
    }
    return map;
  }

  Future<Statement> markPaid(String statementId, double amount) async {
    final data = await _db
        .from('statements')
        .update({
          'paid_amount': amount,
          'paid_at': DateTime.now().toIso8601String(),
          'payment_status': 'paid',
        })
        .eq('id', statementId)
        .select()
        .single();
    return Statement.fromJson(data);
  }

  /// Create or update a statement for one card + statement period. Upserts
  /// on (user_card_id, statement_date) so re-processing the same email is
  /// idempotent, matching this project's statements_user_card_statement_date_key
  /// constraint (see main's SupabaseStatementRepository, same schema).
  Future<Statement> upsertStatement({
    required String userId,
    required String cardId,
    required String userCardId,
    required DateTime statementDate,
    required DateTime dueDate,
    double totalAmount = 0,
    double minimumPayment = 0,
    double closingBalance = 0,
    double availableCredit = 0,
    double rewardsEarned = 0,
    Map<String, dynamic>? metadata,
    int? transactionCount,
  }) async {
    final values = <String, dynamic>{
      'user_id': userId,
      'card_id': cardId,
      'user_card_id': userCardId,
      'statement_date': statementDate.toIso8601String(),
      'due_date': dueDate.toIso8601String(),
      'total_amount': totalAmount,
      'minimum_payment': minimumPayment,
      'closing_balance': closingBalance,
      'available_credit': availableCredit,
      'rewards_earned': rewardsEarned,
      'payment_status': 'pending',
      'processed': true,
    };
    if (transactionCount case final count?) {
      values['transaction_count'] = count;
    }
    final data = await _db
        .from('statements')
        .upsert(
          values,
          // Not sending 'metadata' — the live statements table's PostgREST
          // schema cache doesn't recognize that column on this Supabase
          // project (confirmed via PGRST204 at runtime), even though a
          // migration for it exists on main. Drop until that migration is
          // actually applied here.
          onConflict: 'user_card_id,statement_date',
        )
        .select()
        .single();
    return Statement.fromJson(data);
  }
}
