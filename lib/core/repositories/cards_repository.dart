import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/user_card.dart';

class CardsRepository {
  final SupabaseClient _db;
  CardsRepository(this._db);

  Future<List<UserCard>> getUserCards(String userId) async {
    final data = await _db
        .from('user_cards')
        .select('*, card_catalog(*)')
        .eq('user_id', userId)
        .eq('is_active', true)
        .order('created_at');
    return (data as List).map((e) => UserCard.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UserCard> addUserCard({
    required String userId,
    required String catalogCardId,
    String? lastFourDigits,
    String? cardHolderName,
    double? creditLimit,
    int? statementDate,
    int? dueDate,
  }) async {
    final data = await _db.from('user_cards').insert({
      'user_id': userId,
      'catalog_card_id': catalogCardId,
      if (lastFourDigits != null) 'last_four_digits': lastFourDigits,
      if (cardHolderName != null) 'card_holder_name': cardHolderName,
      if (creditLimit != null) 'credit_limit': creditLimit,
      if (statementDate != null) 'statement_date': statementDate,
      if (dueDate != null) 'due_date': dueDate,
    }).select('*, card_catalog(*)').single();
    return UserCard.fromJson(data as Map<String, dynamic>);
  }

  Future<void> removeUserCard(String userCardId) async {
    await _db.from('user_cards').update({'is_active': false}).eq('id', userCardId);
  }

  /// Placeholder last-4 seen on cards added before real statement data was
  /// available — not a real card number, safe to overwrite once a statement
  /// reveals the actual digits.
  static const placeholderLastFour = '1234';

  /// Backfills last-4 digits and/or credit limit onto a user_card once
  /// they're learned from a parsed statement. Only overwrites last-4 when
  /// it's currently null OR the known placeholder value; a real value the
  /// user entered manually is never clobbered. Credit limit is only filled
  /// when currently null.
  Future<void> backfillCardDetails({
    required String userCardId,
    String? lastFourDigits,
    double? creditLimit,
  }) async {
    if (lastFourDigits == null && creditLimit == null) return;

    final existing = await _db
        .from('user_cards')
        .select('last_four_digits, credit_limit')
        .eq('id', userCardId)
        .single();

    final updates = <String, dynamic>{};
    final existingLastFour = existing['last_four_digits'] as String?;
    if (lastFourDigits != null &&
        (existingLastFour == null || existingLastFour == placeholderLastFour)) {
      updates['last_four_digits'] = lastFourDigits;
    }
    if (creditLimit != null && existing['credit_limit'] == null) {
      updates['credit_limit'] = creditLimit;
    }
    if (updates.isEmpty) return;

    await _db.from('user_cards').update(updates).eq('id', userCardId);
  }

  // Search the catalog — used in add-card flow
  Future<List<Map<String, dynamic>>> searchCatalog(String query) async {
    final data = await _db
        .from('card_catalog')
        .select('id, card_name, bank, network, annual_fee, card_url')
        .eq('is_discontinued', false)
        .or('card_name.ilike.%$query%,bank.ilike.%$query%')
        .order('card_name')
        .limit(20);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Catalog entries for one bank, optionally filtered by card-name typeahead
  /// text — used when resolving a statement email whose bank didn't match
  /// any card the user already has on file.
  Future<List<Map<String, dynamic>>> searchCatalogForBank(String bank, {String query = ''}) async {
    var builder = _db
        .from('card_catalog')
        .select('id, card_name, bank, network, annual_fee, card_url')
        .eq('is_discontinued', false)
        .ilike('bank', '%$bank%');
    if (query.isNotEmpty) {
      builder = builder.ilike('card_name', '%$query%');
    }
    final data = await builder.order('card_name').limit(30);
    return (data as List).cast<Map<String, dynamic>>();
  }
}
