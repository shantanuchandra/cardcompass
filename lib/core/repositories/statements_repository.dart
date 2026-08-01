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
}
