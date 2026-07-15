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

    test('normalizes a legacy percent rate', () {
      final result = normalizeMovieDealRule(
        source({'rate': 15, 'unit': 'percent'}),
      );

      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.discountPercent, 15);
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

    test('rejects non-finite percentage discount values', () {
      final result = normalizeMovieDealRule(
        source({'discount_percent': 'NaN'}),
      );

      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });

    test('rejects non-finite fixed discount values', () {
      final result = normalizeMovieDealRule(
        source({'discount_amount': 'Infinity'}),
      );

      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });

    test('rejects supplied malformed optional fields', () {
      final invalidConfigs = [
        {'discount_percent': 10, 'start_date': 'not-a-date'},
        {'discount_percent': 10, 'txn_ticket_limit': 'many'},
        {'discount_percent': 10, 'max_discount_amount': 'unknown'},
        {'discount_percent': 10, 'min_transaction_amount': 'unknown'},
        {'discount_percent': 10, 'valid_dow': 3},
        {'discount_percent': 10, 'platform': ['BookMyShow', 42]},
      ];

      for (final config in invalidConfigs) {
        final result = normalizeMovieDealRule(source(config));
        expect(result, isA<RejectedMovieDealRule>(), reason: '$config');
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
