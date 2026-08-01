import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/statement.dart';

class StatementsRepository {
  final SupabaseClient _db;
  StatementsRepository(this._db);

  Future<List<Statement>> getUserStatements(String userId, {int limit = 20}) async {
    final data = await _db
        .from('statements')
        .select()
        .eq('user_id', userId)
        .order('statement_date', ascending: false)
        .limit(limit);
    return (data as List).map((e) => Statement.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Latest statement per card — used for the bill panel on the dashboard
  Future<Map<String, Statement>> getLatestStatementPerCard(String userId) async {
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
    return Statement.fromJson(data as Map<String, dynamic>);
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
    final data = await _db.from('statements').upsert(
      {
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
        'metadata': metadata ?? {},
        if (transactionCount != null) 'transaction_count': transactionCount,
      },
      onConflict: 'user_card_id,statement_date',
    ).select().single();
    return Statement.fromJson(data as Map<String, dynamic>);
  }
}
