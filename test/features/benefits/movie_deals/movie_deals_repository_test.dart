// test/features/benefits/movie_deals/movie_deals_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/repositories/movie_deals_repository.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';

class _FakeDataSource implements MovieDealsDataSource {
  _FakeDataSource({
    this.benefits = const [],
    this.mappings = const [],
    this.catalogCards = const [],
    this.userCards = const [],
    this.transactions = const [],
    this.milestones = const [],
    this.confirmations = const [],
  });

  final List<Map<String, dynamic>> benefits;
  final List<Map<String, dynamic>> mappings;
  final List<Map<String, dynamic>> catalogCards;
  final List<Map<String, dynamic>> userCards;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> milestones;
  final List<Map<String, dynamic>> confirmations;
  final List<(String, String, String)> confirmationCalls = [];

  @override
  Future<List<Map<String, dynamic>>> loadMovieRelatedBenefits() async => benefits;

  @override
  Future<List<Map<String, dynamic>>> loadMappings(List<String> benefitIds) async =>
      mappings.where((m) => benefitIds.contains(m['benefit_id'])).toList();

  @override
  Future<List<Map<String, dynamic>>> loadCatalogCards(List<String> cardIds) async =>
      catalogCards.where((c) => cardIds.contains(c['id'])).toList();

  @override
  Future<List<Map<String, dynamic>>> loadActiveUserCards(String userId) async => userCards;

  @override
  Future<List<Map<String, dynamic>>> loadTransactions(
          String userId, List<String> userCardIds) async =>
      transactions;

  @override
  Future<List<Map<String, dynamic>>> loadMilestones(String userId) async => milestones;

  @override
  Future<List<Map<String, dynamic>>> loadConfirmations(List<String> benefitIds) async =>
      confirmations.where((c) => benefitIds.contains(c['benefit_id'])).toList();

  @override
  Future<void> insertConfirmation({
    required String benefitId,
    required String platform,
    required String userId,
  }) async {
    confirmationCalls.add((benefitId, platform, userId));
  }
}

Map<String, dynamic> _benefitRow({
  required String id,
  required String title,
  required Map<String, dynamic> valueConfig,
  List<String> partners = const [],
  Map<String, dynamic> exclusions = const {},
}) =>
    {
      'benefit_id': id,
      'title': title,
      'value_config': valueConfig,
      'partners': partners,
      'exclusions': exclusions,
      'source_url': null,
      'valid_from': null,
      'valid_until': null,
    };

void main() {
  group('MovieDealsSupabaseRepository — source construction', () {
    test('owned status is matched via catalog_card_id, not the user_card row id', () {
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(
            id: 'b1',
            title: 'Test',
            valueConfig: {'discount_type': 'percent', 'discount_percent': 25.0},
          ),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        userCards: [
          {'id': 'user-card-instance-1', 'catalog_card_id': 'catalog-card-1'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      return repository
          .loadSnapshot(
            'user1',
            const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
            now: DateTime(2026, 8, 2),
          )
          .then((snapshot) {
        expect(snapshot.sources, hasLength(1));
        expect(snapshot.sources.first.catalogCardId, 'catalog-card-1');
        expect(
          snapshot.contexts[('catalog-card-1', 'b1')]?.isOwned,
          isTrue,
        );
      });
    });

    test('partners and excludedCategories are extracted from their own columns, not value_config', () {
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(
            id: 'b1',
            title: '3% Cashpoints on Paytm Purchases',
            valueConfig: {'unit': 'percent', 'category': 'utilities,movies', 'base_rate': 3.0},
            partners: ['Paytm'],
            exclusions: {
              'categories': ['wallet_loads', 'rent_payments', 'government_payments'],
            },
          ),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      return repository
          .loadSnapshot(
            'user1',
            const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
            now: DateTime(2026, 8, 2),
          )
          .then((snapshot) {
        final source = snapshot.sources.first;
        expect(source.partners, contains('Paytm'));
        expect(source.excludedCategories, contains('wallet_loads'));
      });
    });

    test('validityStart/validityEnd are extracted from valid_from/valid_until columns', () {
      final row = _benefitRow(
        id: 'b1',
        title: 'Future-dated offer',
        valueConfig: {'discount_type': 'percent', 'discount_percent': 20.0},
      );
      row['valid_from'] = '2026-01-01';
      row['valid_until'] = '2026-12-31';
      final dataSource = _FakeDataSource(
        benefits: [row],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      return repository
          .loadSnapshot(
            'user1',
            const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
            now: DateTime(2026, 8, 2),
          )
          .then((snapshot) {
        final source = snapshot.sources.first;
        expect(source.validityStart, DateTime(2026, 1, 1));
        expect(source.validityEnd, DateTime(2026, 12, 31));
      });
    });
  });

  group('MovieDealsSupabaseRepository — context building', () {
    test('confirmations are scoped per (catalogCardId, benefitId), never unioned across benefits on the same card', () {
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(id: 'b1', title: 'Benefit A', valueConfig: {'discount_type': 'percent', 'discount_percent': 25.0}),
          _benefitRow(id: 'b2', title: 'Benefit B', valueConfig: {'discount_type': 'percent', 'discount_percent': 15.0}),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
          {'benefit_id': 'b2', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        confirmations: [
          {'benefit_id': 'b1', 'platform_key': 'pvr'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      return repository
          .loadSnapshot(
            'user1',
            const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
            now: DateTime(2026, 8, 2),
          )
          .then((snapshot) {
        expect(snapshot.contexts[('catalog-card-1', 'b1')]?.confirmedPlatforms, contains('pvr'));
        expect(snapshot.contexts[('catalog-card-1', 'b2')]?.confirmedPlatforms ?? const {}, isNot(contains('pvr')));
      });
    });

    test('capped usage is unverified when matching transaction metadata lacks a numeric ticket_count', () async {
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(
            id: 'b1', title: 'BOGO',
            valueConfig: {'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 500.0},
            partners: ['BookMyShow'],
          ),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        userCards: [
          {'id': 'user-card-1', 'catalog_card_id': 'catalog-card-1'},
        ],
        transactions: [
          {
            'user_card_id': 'user-card-1',
            'merchant_name': 'BookMyShow',
            'transaction_date': '2026-08-01T10:00:00Z',
            'metadata': <String, dynamic>{},
          },
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        now: DateTime(2026, 8, 2),
      );
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.usageConfidence, MovieDealUsageConfidence.unverified);
    });

    for (final fixture
        in <
          ({
            String label,
            Map<String, dynamic> config,
            String outside,
            String inside,
          })
        >[
          (
            label: 'month',
            config: {
              'discount_type': 'BOGO',
              'max_usage_per_month': 2,
              'max_discount_per_transaction': 500.0,
            },
            outside: '2026-07-31T23:59:59Z',
            inside: '2026-08-01T00:00:00Z',
          ),
          (
            label: 'quarter',
            config: {
              'discount_type': 'BOGO',
              'max_usage_per_period': 2,
              'usage_period': 'quarter',
              'max_discount_per_transaction': 500.0,
            },
            outside: '2026-06-30T23:59:59Z',
            inside: '2026-07-01T00:00:00Z',
          ),
          (
            label: 'year',
            config: {
              'discount_type': 'BOGO',
              'max_usage_per_period': 2,
              'usage_period': 'year',
              'max_discount_per_transaction': 500.0,
            },
            outside: '2025-12-31T23:59:59Z',
            inside: '2026-01-01T00:00:00Z',
          ),
        ]) {
      test(
        '${fixture.label} usage excludes transactions before the current cycle',
        () async {
          final dataSource = _FakeDataSource(
            benefits: [
              _benefitRow(
                id: 'b1',
                title: 'BOGO',
                valueConfig: fixture.config,
                partners: ['BookMyShow'],
              ),
            ],
            mappings: [
              {
                'benefit_id': 'b1',
                'card_id': 'catalog-card-1',
                'display_priority': 0,
              },
            ],
            catalogCards: [
              {'id': 'catalog-card-1', 'card_name': 'Test Card'},
            ],
            userCards: [
              {'id': 'user-card-1', 'catalog_card_id': 'catalog-card-1'},
            ],
            transactions: [
              for (final date in [fixture.outside, fixture.inside])
                {
                  'user_card_id': 'user-card-1',
                  'merchant_name': 'BookMyShow',
                  'transaction_date': date,
                  'metadata': <String, dynamic>{'ticket_count': 1},
                },
            ],
          );

          final snapshot = await MovieDealsSupabaseRepository(dataSource)
              .loadSnapshot(
                'user1',
                const MovieTicketRequest(
                  numberOfTickets: 1,
                  pricePerTicket: 300,
                  preferredPlatform: 'BookMyShow',
                ),
                now: DateTime.utc(2026, 8, 18),
              );

          final context = snapshot.contexts[('catalog-card-1', 'b1')];
          expect(context?.usageConfidence, MovieDealUsageConfidence.verified);
          expect(context?.usedTransactions, 1);
          expect(context?.usedTickets, 1);
        },
      );
    }

    test('milestone spend selects the most recently COMPLETED cycle, not the most recently UPDATED row', () async {
      // A partial current-cycle row (updated recently) must not be preferred
      // over an older, genuinely completed prior cycle (design spec §7).
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(
            id: 'b1', title: 'Monthly Vouchers on Spends',
            valueConfig: {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0},
            partners: ['BookMyShow'],
          ),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        milestones: [
          {
            'card_id': 'catalog-card-1',
            'statement_start_date': '2026-08-01',
            'statement_end_date': '2026-08-31', // current, incomplete cycle
            'total_spending': 10000.0,
            'last_updated': '2026-08-02T09:00:00Z', // most recently touched
          },
          {
            'card_id': 'catalog-card-1',
            'statement_start_date': '2026-07-01',
            'statement_end_date': '2026-07-31', // completed prior cycle
            'total_spending': 85000.0,
            'last_updated': '2026-07-31T23:59:00Z',
          },
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        now: DateTime(2026, 8, 2),
      );
      // Must pick the July (completed, threshold-meeting) row, not the
      // August (current, threshold-missing) one — 85000, not 10000.
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.milestoneSpend, 85000.0);
    });

    test('absent milestone cache leaves milestoneSpend null, not zero', () async {
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(
            id: 'b1', title: 'Monthly Vouchers on Spends',
            valueConfig: {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0},
          ),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        milestones: const [],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        now: DateTime(2026, 8, 2),
      );
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.milestoneSpend, isNull);
    });

    test('confirmPlatform delegates to the data source with the given ids', () async {
      final dataSource = _FakeDataSource();
      final repository = MovieDealsSupabaseRepository(dataSource);

      await repository.confirmPlatform(benefitId: 'b1', platform: 'PVR', userId: 'user1');

      expect(dataSource.confirmationCalls, hasLength(1));
      expect(dataSource.confirmationCalls.first, ('b1', 'PVR', 'user1'));
    });

    test('confirmationCount is read from the confirmation row and threaded onto the context', () async {
      // benefit_platform_confirmation_counts exposes confirmation_count, but
      // the repository previously discarded it after only checking
      // isNotEmpty — the UI could never show "confirmed by N users" without
      // this. Scoped per (catalogCardId, benefitId) like everything else in
      // this context map, never card-wide.
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(id: 'b1', title: 'Benefit A', valueConfig: {'discount_type': 'percent', 'discount_percent': 25.0}),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        confirmations: [
          {'benefit_id': 'b1', 'platform_key': 'pvr', 'confirmation_count': 12},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        now: DateTime(2026, 8, 2),
      );
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.confirmationCount, 12);
    });

    test('a benefit with no confirmation row has a null confirmationCount, never a fabricated 0', () async {
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(id: 'b1', title: 'Benefit A', valueConfig: {'discount_type': 'percent', 'discount_percent': 25.0}),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        now: DateTime(2026, 8, 2),
      );
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.confirmationCount, isNull);
    });

    test('a confirmation row keyed by platform_key (the real view\'s column) still resolves to a non-empty confirmedPlatforms', () async {
      // benefit_platform_confirmation_counts (see the CREATE VIEW in
      // supabase/migrations/20260802100100_benefit_platform_confirmations.sql)
      // selects benefit_id, platform_key, confirmation_count — there is no
      // `platform` column on that view. A prior version of the repository
      // read row['platform'] instead of row['platform_key'], so every real
      // row failed the `platform == null` guard and was silently dropped —
      // confirmedPlatforms could never be non-empty from real data,
      // regardless of how many users had confirmed. This fixture uses the
      // exact key the real view returns to guard against that regression.
      final dataSource = _FakeDataSource(
        benefits: [
          _benefitRow(id: 'b1', title: 'Benefit A', valueConfig: {'discount_type': 'percent', 'discount_percent': 25.0}),
        ],
        mappings: [
          {'benefit_id': 'b1', 'card_id': 'catalog-card-1', 'display_priority': 0},
        ],
        catalogCards: [
          {'id': 'catalog-card-1', 'card_name': 'Test Card'},
        ],
        confirmations: [
          {'benefit_id': 'b1', 'platform_key': 'pvr', 'confirmation_count': 3},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        now: DateTime(2026, 8, 2),
      );
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.confirmedPlatforms, isNotEmpty);
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.confirmedPlatforms, contains('pvr'));
    });
  });
}
