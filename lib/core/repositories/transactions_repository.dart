import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/transaction.dart';
import '../services/mcc_resolver.dart';
import '../services/transaction_categorizer.dart' show validCategories;
import 'paginated_query.dart';

String? parseMerchantCategoryRow(Map<String, dynamic>? row) {
  return row?['category'] as String?;
}

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
    var query = _db.from('transactions').select().eq('user_id', userId);

    if (userCardId != null) query = query.eq('user_card_id', userCardId);
    if (from != null) {
      query = query.gte('transaction_date', from.toIso8601String());
    }
    if (to != null) query = query.lte('transaction_date', to.toIso8601String());
    if (category != null) query = query.eq('category', category);

    final data = await query
        .order('transaction_date', ascending: false)
        .range(offset, offset + limit - 1);

    return (data as List)
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Transaction>> getRecentTransactions(
    String userId, {
    int limit = 10,
  }) async {
    final data = await _db
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .order('transaction_date', ascending: false)
        .limit(limit);
    return (data as List)
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the user's full ledger without depending on one PostgREST
  /// response exceeding the server row cap.
  Future<List<Transaction>> getAllTransactions({required String userId}) {
    return collectPaginated<Transaction>(
      loadPage: (offset, limit) async {
        final data = await _db
            .from('transactions')
            .select()
            .eq('user_id', userId)
            .order('transaction_date', ascending: false)
            .order('id', ascending: true)
            .range(offset, offset + limit - 1);
        return (data as List)
            .map((row) => Transaction.fromJson(row as Map<String, dynamic>))
            .toList(growable: false);
      },
    );
  }

  /// Returns every transaction in a closed reporting window without relying
  /// on one PostgREST response exceeding the server's row cap.
  Future<List<Transaction>> getAllTransactionsInRange({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) {
    return collectPaginated<Transaction>(
      loadPage: (offset, limit) async {
        final data = await _db
            .from('transactions')
            .select()
            .eq('user_id', userId)
            .gte('transaction_date', from.toIso8601String())
            .lte('transaction_date', to.toIso8601String())
            .order('transaction_date', ascending: false)
            .order('id', ascending: true)
            .range(offset, offset + limit - 1);
        return (data as List)
            .map((row) => Transaction.fromJson(row as Map<String, dynamic>))
            .toList(growable: false);
      },
    );
  }

  Future<String?> lookupMerchantCategory(String normalizedMerchantName) async {
    final row = await _db
        .from('merchant_category_map')
        .select('category')
        .eq('merchant_name_normalized', normalizedMerchantName)
        .maybeSingle();
    return parseMerchantCategoryRow(row);
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

  /// Insert one transaction. Silently skips if a row with the same
  /// (user_id, user_card_id, transaction_date, description, amount) already
  /// exists — this project's dedup key, matching main's
  /// idx_transactions_dedup unique index.
  Future<void> addTransaction({
    required String userId,
    required String userCardId,
    required double amount,
    required String description,
    required DateTime transactionDate,
    required String currency,
    String? merchantName,
    String? category,
    String transactionType = 'debit',
    String? location,
    double? rewardEarned,
    String? rewardType,
    String? statementId,
    MccCandidate? mcc,
    Map<String, dynamic>? metadata,
  }) async {
    await _db
        .from('transactions')
        .upsert(
          {
            'user_id': userId,
            'user_card_id': userCardId,
            'amount': amount,
            'description': description,
            'transaction_date': transactionDate.toIso8601String(),
            'currency': currency,
            'merchant_name': merchantName,
            'category': category,
            'transaction_type': transactionType,
            'location': location,
            'reward_earned': rewardEarned,
            'reward_type': rewardType,
            'statement_id': statementId,
            'mcc_code': mcc?.code,
            'mcc_description': mcc?.description,
            'mcc_source': mcc?.source.databaseValue,
            'mcc_confidence': mcc?.confidence,
            'mcc_verified_at': mcc?.verifiedAt?.toIso8601String(),
            'metadata': metadata,
          },
          onConflict:
              'user_id,user_card_id,transaction_date,description,amount',
          ignoreDuplicates: true,
        );
  }

  /// Assembled as ONE .or(...) expression (matching the precedent in
  /// SupabaseMovieDealsDataSource._buildWidenedOrExpression) rather than
  /// chained separate filter calls, which PostgREST would combine as AND
  /// instead of the OR this needs. Reuses [validCategories] from
  /// transaction_categorizer.dart rather than restating the 16-category
  /// list here, so the two can't drift apart.
  static String _buildUncategorizedOrExpression() {
    final quotedCategories = validCategories.map((c) => '"$c"').join(',');
    return 'category.is.null,'
        'category.eq.other,'
        'category.not.in.($quotedCategories)';
  }

  /// Every transaction for [userId] whose category needs backfilling —
  /// NULL, exactly 'other', or any value outside the 16 valid categories
  /// (catches legacy vocabulary like 'dining'/'bills'/'transfer' in one
  /// condition). Used by CategoryBackfillService (a later task).
  Future<List<Transaction>> getUncategorizedTransactions(String userId) async {
    final data = await _db
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .or(_buildUncategorizedOrExpression());
    return (data as List)
        .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Updates just the category and metadata for an existing transaction by
  /// id — used by the backfill job. `addTransaction`'s upsert with
  /// ignoreDuplicates can't be reused here: it silently no-ops on a
  /// dedup-key conflict rather than updating, which is exactly what a
  /// backfill needs to do for a row that already exists.
  Future<void> updateTransactionCategory({
    required String transactionId,
    required String category,
    required Map<String, dynamic> metadata,
  }) async {
    await _db
        .from('transactions')
        .update({'category': category, 'metadata': metadata})
        .eq('id', transactionId);
  }
}
