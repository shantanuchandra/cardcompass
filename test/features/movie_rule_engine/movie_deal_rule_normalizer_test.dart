import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_rule.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/movie_deal_rule_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

MovieBenefitSource source(Map<String, dynamic> valueConfig) =>
    MovieBenefitSource(
      benefitId: 'benefit-1',
      catalogCardId: 'card-1',
      title: 'Movie benefit',
      valueConfig: valueConfig,
    );

void main() {
  group('normalizeMovieDealRule', () {
    test('normalizes discount_percent without offer_type', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 10, 'platform': 'BookMyShow'}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.discountPercent, 10);
      expect(rule.platforms, {'BookMyShow'});
    });

    test('treats a null maximum discount as an absent cap', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 10, 'max_discount_amount': null}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.maximumDiscount, isNull);
    });

    test('treats a null minimum transaction as no minimum', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 10, 'min_transaction_amount': null}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.minimumTransaction, isNull);
    });

    test('infers a percentage rule when offer_type is null', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 10, 'offer_type': null}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.discountPercent, 10);
    });

    test('normalizes a legacy percent rate', () {
      final result = normalizeMovieDealRule(
        source({'rate': 15, 'unit': 'percent'}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.discountPercent, 15);
    });

    test('rejects a malformed supplied unit during inference', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 10, 'unit': 42}),
      );

      expect(result, isA<RejectedMovieDealRule>());
    });

    test('rejects a malformed supplied offer type during inference', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 10, 'offer_type': 42}),
      );

      expect(result, isA<RejectedMovieDealRule>());
    });

    test('rejects an unknown supplied offer type despite a valid percentage',
        () {
      expect(
        normalizeMovieDealRule(
          source({'offer_type': 'BOGUS', 'discount_percent': 10}),
        ),
        isA<RejectedMovieDealRule>(),
      );
    });

    test('rejects an unknown supplied offer type despite a valid fixed amount',
        () {
      expect(
        normalizeMovieDealRule(
          source({'offer_type': 'BOGUS', 'discount_amount': 100}),
        ),
        isA<RejectedMovieDealRule>(),
      );
    });

    test('rejects contradictory supplied units', () {
      final invalidConfigs = [
        {'unit': 'fixed', 'discount_percent': 10},
        {'unit': 'percent', 'discount_amount': 100},
        {'offer_type': 'BOGO', 'discount_percent': 10},
      ];

      for (final config in invalidConfigs) {
        expect(
          normalizeMovieDealRule(source(config)),
          isA<RejectedMovieDealRule>(),
          reason: '$config',
        );
      }
    });

    test('normalizes discount_amount as a fixed discount without defaults', () {
      final result = normalizeMovieDealRule(
        source({'discount_amount': 250}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.fixedDiscount);
      expect(rule.fixedAmount, 250);
      expect(rule.maximumDiscount, isNull);
      expect(rule.minimumTransaction, isNull);
    });

    test('normalizes an explicit BOGO rule', () {
      final result = normalizeMovieDealRule(
        source({'offer_type': 'BOGO', 'free_ticket_count': 1}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.bogo);
      expect(rule.buyCount, 1);
      expect(rule.freeCount, 1);
    });

    test('rejects ambiguous fixed terms rather than assuming 15 percent', () {
      final result = normalizeMovieDealRule(source({'unit': 'fixed'}));

      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });

    test('rejects malformed BOGO records with a reason', () {
      final result = normalizeMovieDealRule(
        source({'offer_type': 'BOGO', 'free_ticket_count': 0}),
      );

      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });

    test('rejects a malformed percentage alias despite a valid fallback', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 'NaN', 'rate': 10, 'unit': 'percent'}),
      );

      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });

    test('rejects a malformed fixed amount alias despite a valid fallback', () {
      final result = normalizeMovieDealRule(
        source({'discount_amount': 'Infinity', 'fixed_amount': 100}),
      );

      expect(result, isA<RejectedMovieDealRule>());
      expect(
        (result as RejectedMovieDealRule).reason,
        contains('discount_amount'),
      );
    });

    test('rejects a malformed milestone threshold despite a valid fallback',
        () {
      final result = normalizeMovieDealRule(
        source({
          'offer_type': 'MILESTONE',
          'milestone_threshold': 'NaN',
          'milestone_currency': 1000,
          'milestone_reward': 100,
        }),
      );

      expect(result, isA<RejectedMovieDealRule>());
      expect(
        (result as RejectedMovieDealRule).reason,
        contains('milestone_threshold'),
      );
    });

    test('rejects supplied malformed optional fields', () {
      final invalidConfigs = [
        {'discount_percent': 10, 'start_date': 'not-a-date'},
        {'discount_percent': 10, 'txn_ticket_limit': 'many'},
        {'discount_percent': 10, 'max_discount_amount': 'unknown'},
        {'discount_percent': 10, 'min_transaction_amount': 'unknown'},
        {'discount_percent': 10, 'valid_dow': 3},
        {
          'discount_percent': 10,
          'platform': ['BookMyShow', 42]
        },
      ];

      for (final config in invalidConfigs) {
        final result = normalizeMovieDealRule(source(config));
        expect(result, isA<RejectedMovieDealRule>(), reason: '$config');
      }
    });

    test('rejects negative supplied commercial aliases outside inferred terms',
        () {
      final invalidConfigs = [
        {'discount_percent': 10, 'max_discount_amount': -1},
        {'discount_percent': 10, 'min_transaction_amount': -1},
        {'discount_percent': 10, 'txn_ticket_limit': -1},
        {'discount_percent': 10, 'transaction_ticket_limit': -1},
        {'discount_percent': 10, 'month_ticket_limit': -1},
        {'discount_percent': 10, 'cycle_ticket_limit': -1},
        {'discount_percent': 10, 'buy_ticket_count': -1},
        {'discount_percent': 10, 'free_count': -1},
        {'discount_percent': 10, 'discount_amount': -1},
        {'discount_percent': 10, 'fixed_amount': -1},
        {'discount_percent': 10, 'milestone_threshold': -1},
        {'discount_percent': 10, 'milestone_currency': -1},
        {'discount_percent': 10, 'milestone_reward': -1},
      ];

      for (final config in invalidConfigs) {
        expect(
          normalizeMovieDealRule(source(config)),
          isA<RejectedMovieDealRule>(),
          reason: '$config',
        );
      }
    });

    test('rejects a malformed supplied BOGO buy ticket count', () {
      final result = normalizeMovieDealRule(
        source({
          'offer_type': 'BOGO',
          'buy_ticket_count': 'one',
          'free_ticket_count': 1,
        }),
      );

      expect(result, isA<RejectedMovieDealRule>());
    });

    test('defensively copies canonical model collections', () {
      final platforms = {'BookMyShow'};
      final rule = MovieDealRule(
        benefitId: 'benefit-1',
        catalogCardId: 'card-1',
        title: 'Movie benefit',
        offerType: MovieDealOfferType.percentDiscount,
        platforms: platforms,
      );

      platforms.add('Paytm Movies');

      expect(rule.platforms, {'BookMyShow'});
      expect(() => rule.platforms.add('PVR'), throwsUnsupportedError);
    });
  });
}
