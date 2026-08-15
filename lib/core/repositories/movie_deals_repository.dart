// lib/core/repositories/movie_deals_repository.dart
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';

export 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';

/// A read-only view of the data required to evaluate movie deals.
/// [contexts] is keyed by (catalogCardId, benefitId) — design spec §5's
/// confirmation-scoping correction — never catalogCardId alone.
class MovieDealsSnapshot {
  MovieDealsSnapshot({
    required List<MovieBenefitSource> sources,
    required Map<(String, String), MovieDealContext> contexts,
  })  : sources = List.unmodifiable(sources),
        contexts = Map.unmodifiable(contexts);

  final List<MovieBenefitSource> sources;
  final Map<(String, String), MovieDealContext> contexts;
}

abstract interface class MovieDealsRepository {
  /// [now] gates milestone cycle-completion (§7) and is threaded explicitly
  /// — never DateTime.now() internally — so callers can pass a fixed value
  /// in tests, matching movie_deal_evaluator.dart's evaluateMovieDeals()
  /// pattern. A prior version called DateTime.now() internally here, which
  /// made a milestone-cycle-selection test's correctness depend on the
  /// wall-clock date at whatever moment the suite happened to run — the
  /// test passed only because its hardcoded fixture dates were, by
  /// coincidence, in the past on the day it was written, and would have
  /// started failing once real time passed the fixture's later date.
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request, {
    required DateTime now,
  });

  /// Records a user's report that [benefitId] worked at [platform]
  /// (design spec §6). Write-only, immutable; no update/delete from the
  /// client.
  Future<void> confirmPlatform({
    required String benefitId,
    required String platform,
    required String userId,
  });
}

/// The small read/write surface used by [MovieDealsSupabaseRepository]. Kept
/// separate from Supabase query builders so the repository is deterministic
/// to unit-test without credentials.
abstract interface class MovieDealsDataSource {
  /// Design spec §4.1 — widened fetch as ONE assembled .or(...) expression,
  /// never chained separate PostgREST calls (chaining combines as AND, the
  /// opposite of "matches any" — see the concrete implementation below).
  Future<List<Map<String, dynamic>>> loadMovieRelatedBenefits();
  Future<List<Map<String, dynamic>>> loadMappings(List<String> benefitIds);
  Future<List<Map<String, dynamic>>> loadCatalogCards(List<String> cardIds);
  Future<List<Map<String, dynamic>>> loadActiveUserCards(String userId);
  Future<List<Map<String, dynamic>>> loadTransactions(
    String userId,
    List<String> userCardIds,
  );
  Future<List<Map<String, dynamic>>> loadMilestones(String userId);
  Future<List<Map<String, dynamic>>> loadConfirmations(List<String> benefitIds);
  Future<void> insertConfirmation({
    required String benefitId,
    required String platform,
    required String userId,
  });
}

class MovieDealsSupabaseRepository implements MovieDealsRepository {
  MovieDealsSupabaseRepository(this._dataSource);

  final MovieDealsDataSource _dataSource;

  @override
  Future<void> confirmPlatform({
    required String benefitId,
    required String platform,
    required String userId,
  }) {
    return _dataSource.insertConfirmation(
      benefitId: benefitId,
      platform: platform,
      userId: userId,
    );
  }

  @override
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request, {
    required DateTime now,
  }) async {
    final benefits = await _dataSource.loadMovieRelatedBenefits();
    if (benefits.isEmpty) {
      return MovieDealsSnapshot(sources: const [], contexts: const {});
    }

    final benefitIds = benefits.map(_idForBenefit).whereType<String>().toList();
    final mappings = await _dataSource.loadMappings(benefitIds);
    final cardIds =
        mappings.map(_idForMappingCard).whereType<String>().toSet().toList();
    final cards = cardIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _dataSource.loadCatalogCards(cardIds);
    final userCards = await _dataSource.loadActiveUserCards(userId);
    final confirmations = await _dataSource.loadConfirmations(benefitIds);

    final benefitById = {
      for (final benefit in benefits) _idForBenefit(benefit): benefit,
    };
    final cardById = {for (final card in cards) _string(card['id']): card};
    final activeUserCardByCatalogId = <String, Map<String, dynamic>>{};
    for (final userCard in userCards) {
      final catalogCardId = _string(userCard['catalog_card_id']);
      if (catalogCardId != null) {
        activeUserCardByCatalogId[catalogCardId] = userCard;
      }
    }

    // Design spec §5 correction: keyed by benefitId, never unioned to the
    // card level.
    final confirmedPlatformsByBenefit = <String, Set<String>>{};
    for (final row in confirmations) {
      final benefitId = _string(row['benefit_id']);
      final platform = _string(row['platform']);
      if (benefitId == null || platform == null) continue;
      confirmedPlatformsByBenefit.putIfAbsent(benefitId, () => {}).add(platform);
    }

    final sources = <MovieBenefitSource>[];
    for (final mapping in mappings) {
      final benefit = benefitById[_idForBenefit(mapping)];
      final cardId = _idForMappingCard(mapping);
      final card = cardId == null ? null : cardById[cardId];
      if (benefit == null || cardId == null || card == null) continue;

      sources.add(MovieBenefitSource(
        benefitId: _idForBenefit(benefit)!,
        catalogCardId: cardId,
        title: _string(benefit['title']) ?? '',
        valueConfig: _jsonMap(benefit['value_config']),
        partners: _jsonStringSet(benefit['partners']),
        excludedCategories: _exclusionCategories(benefit['exclusions']),
        sourceUrl: _string(benefit['source_url']),
        cardName: _string(card['card_name']),
        displayPriority: _integer(mapping['display_priority']) ?? 0,
        validityStart: _date(benefit['valid_from']),
        validityEnd: _date(benefit['valid_until']),
      ));
    }

    final ownedUserCardIds = activeUserCardByCatalogId.values
        .map((card) => _string(card['id']))
        .whereType<String>()
        .toList();
    final transactions = ownedUserCardIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _dataSource.loadTransactions(userId, ownedUserCardIds);
    final milestones = await _dataSource.loadMilestones(userId);
    // Design spec §7 correction: select the row whose statement_end_date is
    // the most recent one strictly BEFORE now — the most recently COMPLETED
    // cycle — never the row with the newest last_updated, which may be a
    // still-accumulating current cycle. `now` is the caller-supplied
    // parameter, never DateTime.now() — see the loadSnapshot doc comment.
    final spendByCatalogCardId = <String, double>{};
    final bestEndDateByCard = <String, DateTime>{};
    for (final milestone in milestones) {
      final cardId = _string(milestone['card_id']);
      final spending = _number(milestone['total_spending']);
      final endDate = _date(milestone['statement_end_date']);
      if (cardId == null || spending == null || endDate == null) continue;
      if (endDate.isAfter(now)) continue; // not yet completed
      final currentBest = bestEndDateByCard[cardId];
      if (currentBest == null || endDate.isAfter(currentBest)) {
        bestEndDateByCard[cardId] = endDate;
        spendByCatalogCardId[cardId] = spending;
      }
    }

    final contexts = <(String, String), MovieDealContext>{};
    for (final source in sources) {
      final userCard = activeUserCardByCatalogId[source.catalogCardId];
      final isOwned = userCard != null;
      final userCardId = userCard == null ? null : _string(userCard['id']);
      final matching = userCardId == null
          ? const <Map<String, dynamic>>[]
          : transactions
              .where((row) =>
                  _string(row['user_card_id']) == userCardId &&
                  _matchesRequest(row, request))
              .toList();
      final verified = matching.isNotEmpty && matching.every(_hasNumericTicketCount);
      final usedTickets = verified
          ? matching.fold<int>(
              0, (sum, row) => sum + _integer(_metadata(row)['ticket_count'])!)
          : 0;
      contexts[(source.catalogCardId, source.benefitId)] = MovieDealContext(
        isOwned: isOwned,
        usageConfidence: verified
            ? MovieDealUsageConfidence.verified
            : MovieDealUsageConfidence.unverified,
        usedTickets: usedTickets,
        usedTransactions: verified ? matching.length : 0,
        milestoneSpend: spendByCatalogCardId[source.catalogCardId],
        confirmedPlatforms: confirmedPlatformsByBenefit[source.benefitId] ?? const {},
      );
    }
    return MovieDealsSnapshot(sources: sources, contexts: contexts);
  }
}

/// Design spec §4.1 — a single assembled .or(...) expression, not chained
/// separate PostgREST calls (which combine as AND by default). Design spec
/// §7 — includes transaction_date (required to bound cycle-window/
/// prior-month checks). Design spec §7 — milestone query selects
/// statement_start_date/statement_end_date, not just total_spending/
/// last_updated, and matches the SAME widened category set §4.1 uses for
/// benefits (not a hardcoded entertainment-only filter — a real row
/// "Monthly Milestone Benefit" is tagged lifestyle).
class SupabaseMovieDealsDataSource implements MovieDealsDataSource {
  SupabaseMovieDealsDataSource(this._client);

  final SupabaseClient _client;

  static const _movieKeywords = ['movie', 'cinema', 'bookmyshow', 'pvr', 'inox', 'cinepolis'];
  static const _widenedCategories = ['entertainment', 'lifestyle', 'dining', 'rewards', 'offers'];

  static String _buildWidenedOrExpression() {
    final keywordClauses = _movieKeywords
        .expand((k) => ['title.ilike.%$k%', 'description.ilike.%$k%'])
        .join(',');
    return 'benefit_category.eq.entertainment,'
        'value_config->>category.ilike.%movie%,'
        'value_config->>discount_type.ilike.%movie%,'
        '$keywordClauses';
  }

  @override
  Future<List<Map<String, dynamic>>> loadMovieRelatedBenefits() async {
    final rows = _rows(await _client
        .from('benefits')
        .select('benefit_id, title, value_config, source_url, partners, exclusions, valid_from, valid_until')
        .eq('is_active', true)
        .or(_buildWidenedOrExpression()));
    return rows;
  }

  @override
  Future<List<Map<String, dynamic>>> loadMappings(List<String> benefitIds) async =>
      benefitIds.isEmpty
          ? const []
          : _rows(await _client
              .from('card_benefit_mapping')
              .select('benefit_id, card_id, display_priority')
              .inFilter('benefit_id', benefitIds));

  @override
  Future<List<Map<String, dynamic>>> loadCatalogCards(List<String> cardIds) async =>
      cardIds.isEmpty
          ? const []
          : _rows(await _client
              .from('card_catalog')
              .select('id, card_name')
              .inFilter('id', cardIds));

  @override
  Future<List<Map<String, dynamic>>> loadActiveUserCards(String userId) async =>
      _rows(await _client
          .from('user_cards')
          .select('id, catalog_card_id')
          .eq('user_id', userId)
          .eq('is_active', true));

  @override
  Future<List<Map<String, dynamic>>> loadTransactions(
          String userId, List<String> userCardIds) async =>
      userCardIds.isEmpty
          ? const []
          : _rows(await _client
              .from('transactions')
              .select('user_card_id, merchant_name, transaction_date, metadata')
              .eq('user_id', userId)
              .inFilter('user_card_id', userCardIds));

  @override
  Future<List<Map<String, dynamic>>> loadMilestones(String userId) async =>
      _rows(await _client
          .from('statement_milestone_cache')
          .select('card_id, statement_start_date, statement_end_date, total_spending')
          .eq('user_id', userId)
          .inFilter('benefit_category', _widenedCategories));

  @override
  Future<List<Map<String, dynamic>>> loadConfirmations(List<String> benefitIds) async =>
      benefitIds.isEmpty
          ? const []
          : _rows(await _client
              .from('benefit_platform_confirmation_counts')
              .select('benefit_id, platform_key')
              .inFilter('benefit_id', benefitIds)
              .gt('confirmation_count', 0));

  @override
  Future<void> insertConfirmation({
    required String benefitId,
    required String platform,
    required String userId,
  }) async {
    await _client.from('benefit_platform_confirmations').upsert(
      {'benefit_id': benefitId, 'platform': platform, 'user_id': userId},
      onConflict: 'user_id,benefit_id,platform_key',
      ignoreDuplicates: true,
    );
  }
}

List<Map<String, dynamic>> _rows(dynamic value) => (value as List)
    .map((row) => Map<String, dynamic>.from(row as Map))
    .toList();

String? _string(dynamic value) => value == null ? null : value.toString();
String? _idForBenefit(Map<String, dynamic> row) => _string(row['benefit_id']);
String? _idForMappingCard(Map<String, dynamic> row) => _string(row['card_id']);
int? _integer(dynamic value) => value is int
    ? value
    : value is num && value == value.roundToDouble()
        ? value.toInt()
        : null;
double? _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

DateTime? _date(dynamic value) {
  final s = _string(value);
  return s == null ? null : DateTime.tryParse(s);
}

Map<String, dynamic> _jsonMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  return const {};
}

Set<String> _jsonStringSet(dynamic value) {
  if (value is List) return value.whereType<String>().toSet();
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded is List) return decoded.whereType<String>().toSet();
  }
  return const {};
}

/// exclusions is a JSONB object shaped like
/// {"categories": [...], "mcc_codes": [...], "merchants": [...], ...}
/// (design spec §4.2/§4.4) — only .categories is ever consumed today
/// (rewardMultiplier's excludedCategories).
Set<String> _exclusionCategories(dynamic value) {
  final map = _jsonMap(value);
  return _jsonStringSet(map['categories']);
}

Map<String, dynamic> _metadata(Map<String, dynamic> transaction) {
  final metadata = transaction['metadata'];
  return metadata is Map ? Map<String, dynamic>.from(metadata) : const {};
}

bool _hasNumericTicketCount(Map<String, dynamic> transaction) =>
    _integer(_metadata(transaction)['ticket_count']) != null;

bool _matchesRequest(
    Map<String, dynamic> transaction, MovieTicketRequest request) {
  final requested = request.preferredPlatform ?? request.preferredCinema;
  if (requested == null || requested.trim().isEmpty) return false;
  final wanted = requested.trim().toLowerCase();
  final metadata = _metadata(transaction);
  final values = [
    metadata['platform'],
    metadata['merchant'],
    transaction['merchant_name'],
  ];
  return values
      .whereType<String>()
      .any((value) => value.trim().toLowerCase() == wanted);
}
