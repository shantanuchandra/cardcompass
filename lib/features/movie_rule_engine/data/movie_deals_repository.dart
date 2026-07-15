import 'dart:convert';

import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_candidate.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_rule.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A read-only view of the data required to evaluate movie deals.
class MovieDealsSnapshot {
  MovieDealsSnapshot({
    required List<MovieBenefitSource> sources,
    required Map<String, MovieDealContext> contexts,
  })  : sources = List.unmodifiable(sources),
        contexts = Map.unmodifiable(contexts);

  final List<MovieBenefitSource> sources;
  final Map<String, MovieDealContext> contexts;
}

abstract interface class MovieDealsRepository {
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  );
}

/// The small read surface used by [MovieDealsSupabaseRepository].
///
/// Keeping it separate from Supabase query builders makes the repository
/// deterministic to unit-test and prevents the evaluator path from requiring
/// credentials.
abstract interface class MovieDealsDataSource {
  Future<List<Map<String, dynamic>>> loadActiveEntertainmentBenefits();
  Future<List<Map<String, dynamic>>> loadMappings(List<String> benefitIds);
  Future<List<Map<String, dynamic>>> loadCatalogCards(List<String> cardIds);
  Future<List<Map<String, dynamic>>> loadActiveUserCards(String userId);
  Future<List<Map<String, dynamic>>> loadTransactions(
    String userId,
    List<String> userCardIds,
  );
  Future<List<Map<String, dynamic>>> loadMilestones(String userId);
}

/// Existing-schema, read-only movie-deal repository.
class MovieDealsSupabaseRepository implements MovieDealsRepository {
  MovieDealsSupabaseRepository(this._dataSource);

  final MovieDealsDataSource _dataSource;

  @override
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  ) async {
    final benefits = await _dataSource.loadActiveEntertainmentBenefits();
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

    final benefitById = {
      for (final benefit in benefits) _idForBenefit(benefit): benefit
    };
    final cardById = {for (final card in cards) _string(card['id']): card};
    final activeUserCardByCatalogId = <String, Map<String, dynamic>>{};
    for (final userCard in userCards) {
      final catalogCardId = _string(userCard['catalog_card_id']);
      if (catalogCardId != null)
        activeUserCardByCatalogId[catalogCardId] = userCard;
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
        valueConfig: _valueConfig(benefit['value_config']),
        sourceUrl: _string(benefit['source_url']),
        cardName: _string(card['card_name']),
        displayPriority: _integer(mapping['display_priority']) ?? 0,
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
    final spendByCatalogCardId = <String, double>{};
    for (final milestone in milestones) {
      final cardId = _string(milestone['card_id']);
      final spending = _number(milestone['total_spending']);
      if (cardId != null &&
          spending != null &&
          !spendByCatalogCardId.containsKey(cardId)) {
        spendByCatalogCardId[cardId] = spending;
      }
    }

    final sourcesByCard = <String, List<MovieBenefitSource>>{};
    for (final source in sources) {
      sourcesByCard.putIfAbsent(source.catalogCardId, () => []).add(source);
    }
    final contexts = <String, MovieDealContext>{};
    for (final entry in sourcesByCard.entries) {
      final userCard = activeUserCardByCatalogId[entry.key];
      final isOwned = userCard != null;
      final capped = entry.value.any(_hasUsageCap);
      final userCardId = userCard == null ? null : _string(userCard['id']);
      final matching = userCardId == null
          ? const <Map<String, dynamic>>[]
          : transactions
              .where((row) =>
                  _string(row['user_card_id']) == userCardId &&
                  _matchesRequest(row, request))
              .toList();
      final verified = capped &&
          matching.isNotEmpty &&
          matching.every(_hasNumericTicketCount);
      final usedTickets = verified
          ? matching.fold<int>(
              0, (sum, row) => sum + _integer(_metadata(row)['ticket_count'])!)
          : 0;
      contexts[entry.key] = MovieDealContext(
        isOwned: isOwned,
        usageConfidence: verified
            ? MovieDealUsageConfidence.verified
            : MovieDealUsageConfidence.unverified,
        usedTickets: usedTickets,
        usedTransactions: verified ? matching.length : 0,
        milestoneSpend: spendByCatalogCardId[entry.key],
      );
    }
    return MovieDealsSnapshot(sources: sources, contexts: contexts);
  }
}

/// Supabase implementation containing only SELECT queries against the existing
/// schema. It is intentionally injectable for tests and offline use.
class SupabaseMovieDealsDataSource implements MovieDealsDataSource {
  SupabaseMovieDealsDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> loadActiveEntertainmentBenefits() async =>
      _rows(await _client
          .from('benefits')
          .select('benefit_id, title, value_config, source_url')
          .eq('benefit_category', 'entertainment')
          .eq('is_active', true));

  @override
  Future<List<Map<String, dynamic>>> loadMappings(
          List<String> benefitIds) async =>
      benefitIds.isEmpty
          ? const []
          : _rows(await _client
              .from('card_benefit_mapping')
              .select('benefit_id, card_id, display_priority')
              .inFilter('benefit_id', benefitIds));

  @override
  Future<List<Map<String, dynamic>>> loadCatalogCards(
          List<String> cardIds) async =>
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
              .select('user_card_id, merchant_name, metadata')
              .eq('user_id', userId)
              .inFilter('user_card_id', userCardIds));

  @override
  Future<List<Map<String, dynamic>>> loadMilestones(String userId) async =>
      _rows(await _client
          .from('statement_milestone_cache')
          .select('card_id, total_spending, last_updated')
          .eq('user_id', userId)
          .eq('benefit_category', 'entertainment')
          .order('last_updated', ascending: false));
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

Map<String, dynamic> _valueConfig(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String) {
    final decoded = jsonDecode(value);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  }
  return const {};
}

bool _hasUsageCap(MovieBenefitSource source) =>
    _integer(source.valueConfig['cycle_ticket_limit']) != null ||
    _integer(source.valueConfig['cycle_transaction_limit']) != null;

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
    transaction['merchant_name']
  ];
  return values
      .whereType<String>()
      .any((value) => value.trim().toLowerCase() == wanted);
}
