import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_platform_aliases.dart';

void main() {
  group('eligibleMoviePlatformsFor', () {
    test('single-purpose bogo rule resolves its one partner unambiguously', () {
      final rule = MovieDealRule(
        benefitId: 'b1',
        catalogCardId: 'c1',
        title: 'Twin ticket treats',
        offerType: MovieDealOfferType.bogo,
        partners: const {'Zomato'},
      );
      expect(eligibleMoviePlatformsFor(rule), {'Zomato'});
    });

    test('multi-partner milestone row excludes non-movie partners via the registry', () {
      // Real row: "Monthly Vouchers on Spends" — partners: ["Uber",
      // "cult.fit Live", "BookMyShow", "TataCliQ"] (design spec §4.3/§8).
      final rule = MovieDealRule(
        benefitId: 'b2',
        catalogCardId: 'c2',
        title: 'Monthly Vouchers on Spends',
        offerType: MovieDealOfferType.milestone,
        partners: const {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'},
      );
      final result = eligibleMoviePlatformsFor(rule);
      expect(result, {'BookMyShow'});
      expect(result, isNot(contains('Uber')));
      expect(result, isNot(contains('cult.fit Live')));
      expect(result, isNot(contains('TataCliQ')));
    });

    test('a rewardMultiplier row with only non-movie partners yields an empty set', () {
      final rule = MovieDealRule(
        benefitId: 'b3',
        catalogCardId: 'c3',
        title: 'Hypothetical non-movie multiplier',
        offerType: MovieDealOfferType.rewardMultiplier,
        partners: const {'Swiggy', 'OYO'},
      );
      expect(eligibleMoviePlatformsFor(rule), isEmpty);
    });

    test('case-insensitive alias matching normalizes "Bookmyshow" and "BookMyShow" identically', () {
      // Real row: "Instant Discount on Bookmyshow" uses lowercase-m spelling
      // (design spec §4.4) — must resolve to the same canonical value.
      final rule = MovieDealRule(
        benefitId: 'b4',
        catalogCardId: 'c4',
        title: 'Instant Discount on Bookmyshow',
        offerType: MovieDealOfferType.percentDiscount,
        partners: const {'Bookmyshow'},
      );
      expect(eligibleMoviePlatformsFor(rule), {'BookMyShow'});
    });

    test('an empty partners set yields an empty eligibleMoviePlatforms set', () {
      final rule = MovieDealRule(
        benefitId: 'b5',
        catalogCardId: 'c5',
        title: '25% Off on Movie Tickets',
        offerType: MovieDealOfferType.percentDiscount,
      );
      expect(eligibleMoviePlatformsFor(rule), isEmpty);
    });
  });
}
