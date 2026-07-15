import 'package:cardcompass/features/movie_rule_engine/data/movie_deals_repository.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_candidate.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const request = MovieTicketRequest(
    numberOfTickets: 2,
    pricePerTicket: 300,
    preferredPlatform: 'BookMyShow',
  );

  test('matches active ownership through catalog_card_id and mapping card_id',
      () async {
    final source = FakeMovieDealsDataSource(
      benefits: [
        {
          'benefit_id': 'benefit-1',
          'title': 'Movie offer',
          'value_config': {'discount_percent': 10}
        },
      ],
      mappings: [
        {
          'benefit_id': 'benefit-1',
          'card_id': 'catalog-card',
          'display_priority': 3
        },
      ],
      cards: [
        {'id': 'catalog-card', 'card_name': 'Correct catalog card'},
      ],
      userCards: [
        {
          'id': 'user-card',
          'catalog_card_id': 'catalog-card',
          'is_active': true
        },
        {
          'id': 'inactive-user-card',
          'catalog_card_id': 'other-card',
          'is_active': false
        },
      ],
    );

    final snapshot = await MovieDealsSupabaseRepository(source)
        .loadSnapshot('user-1', request);

    expect(snapshot.sources, hasLength(1));
    expect(snapshot.sources.single.catalogCardId, 'catalog-card');
    expect(snapshot.sources.single.cardName, 'Correct catalog card');
    expect(snapshot.contexts['catalog-card']!.isOwned, isTrue);
    expect(source.requestedCatalogCardIds, ['catalog-card']);
  });

  test(
      'marks capped usage unverified when matching transaction lacks numeric ticket_count',
      () async {
    final source = FakeMovieDealsDataSource(
      benefits: [
        {
          'benefit_id': 'benefit-1',
          'title': 'Capped movie offer',
          'value_config': {'discount_percent': 10, 'cycle_ticket_limit': 2},
        },
      ],
      mappings: [
        {'benefit_id': 'benefit-1', 'card_id': 'catalog-card'},
      ],
      cards: [
        {'id': 'catalog-card', 'card_name': 'Card'},
      ],
      userCards: [
        {'id': 'user-card', 'catalog_card_id': 'catalog-card'},
      ],
      transactions: [
        {
          'user_card_id': 'user-card',
          'merchant_name': 'BookMyShow',
          'metadata': {'platform': 'BookMyShow', 'ticket_count': 'two'},
        },
      ],
    );

    final snapshot = await MovieDealsSupabaseRepository(source)
        .loadSnapshot('user-1', request);

    expect(snapshot.contexts['catalog-card']!.usageConfidence,
        MovieDealUsageConfidence.unverified);
  });

  test(
      'verifies and aggregates capped usage from matching platform or merchant transactions',
      () async {
    final source = FakeMovieDealsDataSource(
      benefits: [
        {
          'benefit_id': 'benefit-1',
          'title': 'Capped movie offer',
          'value_config': {'discount_percent': 10, 'cycle_ticket_limit': 4},
        },
      ],
      mappings: [
        {'benefit_id': 'benefit-1', 'card_id': 'catalog-card'},
      ],
      cards: [
        {'id': 'catalog-card', 'card_name': 'Card'},
      ],
      userCards: [
        {'id': 'user-card', 'catalog_card_id': 'catalog-card'},
      ],
      transactions: [
        {
          'user_card_id': 'user-card',
          'merchant_name': 'Cinema partner',
          'metadata': {'platform': 'BookMyShow', 'ticket_count': 2},
        },
        {
          'user_card_id': 'user-card',
          'merchant_name': 'BookMyShow',
          'metadata': {'ticket_count': 1},
        },
      ],
    );

    final snapshot = await MovieDealsSupabaseRepository(source)
        .loadSnapshot('user-1', request);

    final context = snapshot.contexts['catalog-card']!;
    expect(context.usageConfidence, MovieDealUsageConfidence.verified);
    expect(context.usedTickets, 3);
    expect(context.usedTransactions, 2);
  });

  test('returns unavailable milestone spending when cache is absent', () async {
    final source = FakeMovieDealsDataSource(
      benefits: [
        {
          'benefit_id': 'benefit-1',
          'title': 'Milestone movie offer',
          'value_config': {'discount_percent': 10, 'milestone_threshold': 1000},
        },
      ],
      mappings: [
        {'benefit_id': 'benefit-1', 'card_id': 'catalog-card'},
      ],
      cards: [
        {'id': 'catalog-card', 'card_name': 'Card'},
      ],
      userCards: [
        {'id': 'user-card', 'catalog_card_id': 'catalog-card'},
      ],
    );

    final snapshot = await MovieDealsSupabaseRepository(source)
        .loadSnapshot('user-1', request);

    expect(snapshot.contexts['catalog-card']!.milestoneSpend, isNull);
  });
}

class FakeMovieDealsDataSource implements MovieDealsDataSource {
  FakeMovieDealsDataSource({
    this.benefits = const [],
    this.mappings = const [],
    this.cards = const [],
    this.userCards = const [],
    this.transactions = const [],
    this.milestones = const [],
  });

  final List<Map<String, dynamic>> benefits;
  final List<Map<String, dynamic>> mappings;
  final List<Map<String, dynamic>> cards;
  final List<Map<String, dynamic>> userCards;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> milestones;
  List<String> requestedCatalogCardIds = [];

  @override
  Future<List<Map<String, dynamic>>> loadActiveEntertainmentBenefits() async =>
      benefits;

  @override
  Future<List<Map<String, dynamic>>> loadActiveUserCards(String userId) async =>
      userCards;

  @override
  Future<List<Map<String, dynamic>>> loadCatalogCards(
      List<String> cardIds) async {
    requestedCatalogCardIds = cardIds;
    return cards;
  }

  @override
  Future<List<Map<String, dynamic>>> loadMappings(
          List<String> benefitIds) async =>
      mappings;

  @override
  Future<List<Map<String, dynamic>>> loadMilestones(String userId) async =>
      milestones;

  @override
  Future<List<Map<String, dynamic>>> loadTransactions(
          String userId, List<String> userCardIds) async =>
      transactions;
}
