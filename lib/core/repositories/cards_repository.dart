import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/user_card.dart';

bool catalogEntryMatchesQuery(Map<String, dynamic> entry, String query) {
  final normalizedQuery = query
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (normalizedQuery.isEmpty) return true;
  final labels = <String>[
    if (entry['card_name'] is String) entry['card_name'] as String,
    for (final alias in entry['card_catalog_aliases'] as List? ?? const [])
      if (alias is Map && alias['alias'] is String) alias['alias'] as String,
  ];
  return labels.any(
    (label) => label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .contains(normalizedQuery),
  );
}

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
    return (data as List)
        .map((e) => UserCard.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final values = <String, dynamic>{
      'user_id': userId,
      'catalog_card_id': catalogCardId,
    };
    if (lastFourDigits != null) values['last_four_digits'] = lastFourDigits;
    if (cardHolderName != null) values['card_holder_name'] = cardHolderName;
    if (creditLimit != null) values['credit_limit'] = creditLimit;
    if (statementDate != null) values['statement_date'] = statementDate;
    if (dueDate != null) values['due_date'] = dueDate;
    final data = await _db
        .from('user_cards')
        .insert(values)
        .select('*, card_catalog(*)')
        .single();
    return UserCard.fromJson(data);
  }

  Future<void> removeUserCard(String userCardId) async {
    await _db
        .from('user_cards')
        .update({'is_active': false})
        .eq('id', userCardId);
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
  Future<List<Map<String, dynamic>>> searchCatalogForBank(
    String bank, {
    String query = '',
  }) async {
    var builder = _db
        .from('card_catalog')
        .select(
          'id, card_name, bank, network, annual_fee, card_url, '
          'card_catalog_aliases(alias, normalized_alias, evidence_type)',
        )
        .eq('is_discontinued', false)
        .ilike('bank', '%$bank%');
    final data = await builder.order('card_name').limit(100);
    return (data as List)
        .cast<Map<String, dynamic>>()
        .where((entry) => catalogEntryMatchesQuery(entry, query))
        .take(30)
        .toList(growable: false);
  }
}
