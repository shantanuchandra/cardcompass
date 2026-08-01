import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/transaction.dart';

class TransactionsRepository {
  final SupabaseClient _db;
  TransactionsRepository(this._db);

  Future<List<Transaction>> getTransactions({
    required String userId,
    String? userCardId,
    DateTime? from,
    DateTime? to,
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _db
        .from('transactions')
        .select()
        .eq('user_id', userId);

    if (userCardId != null) query = query.eq('user_card_id', userCardId);
    if (from != null) query = query.gte('transaction_date', from.toIso8601String());
    if (to != null) query = query.lte('transaction_date', to.toIso8601String());
    if (category != null) query = query.eq('category', category);

    final data = await query
        .order('transaction_date', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Transaction>> getRecentTransactions(String userId, {int limit = 10}) async {
    final data = await _db
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .order('transaction_date', ascending: false)
        .limit(limit);
    return (data as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Total spend for current month, grouped by category
  Future<Map<String, double>> getMonthlySpendByCategory(String userId) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final txns = await getTransactions(
      userId: userId,
      from: start,
      to: now,
      limit: 500,
    );
    final map = <String, double>{};
    for (final t in txns) {
      if (!t.isDebit) continue;
      final cat = t.category ?? 'Other';
      map[cat] = (map[cat] ?? 0) + t.amount;
    }
    return map;
  }
}
