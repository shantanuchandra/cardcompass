import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';

void main() {
  group('MovieDealRule', () {
    test('bogo rule stores per-transaction cap, cycle redemption limit, and partners', () {
      // Real row: "Twin ticket treats" — partners: ["Zomato"] (design spec §4.3/§4.4).
      final rule = MovieDealRule(
        benefitId: 'b1',
        catalogCardId: 'c1',
        title: 'Twin ticket treats',
        offerType: MovieDealOfferType.bogo,
        buyCount: 1,
        freeCount: 1,
        perTransactionCap: 500,
        cycleRedemptionLimit: 2,
        partners: {'Zomato'},
      );

      expect(rule.offerType, MovieDealOfferType.bogo);
      expect(rule.buyCount, 1);
      expect(rule.freeCount, 1);
      expect(rule.perTransactionCap, 500);
      expect(rule.cycleRedemptionLimit, 2);
      expect(rule.partners, contains('Zomato'));
      expect(rule.validityStart, isNull);
      expect(rule.validityEnd, isNull);
    });

    test('rewardMultiplier rule stores rate, unit, qualifying and excluded categories', () {
      // Real row: "3% Cashpoints on Paytm Purchases" — exclusions.categories:
      // ["wallet_loads", "rent_payments", "government_payments"] (design spec §4.2/§4.4).
      final rule = MovieDealRule(
        benefitId: 'b2',
        catalogCardId: 'c2',
        title: '3% Cashpoints on Paytm Purchases',
        offerType: MovieDealOfferType.rewardMultiplier,
        rewardMultiplierRate: 3.0,
        rewardMultiplierUnit: 'percent',
        qualifyingCategories: const {'utilities', 'movies'},
        excludedCategories: const {'wallet_loads', 'rent_payments', 'government_payments'},
        partners: const {'Paytm'},
      );

      expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
      expect(rule.rewardMultiplierRate, 3.0);
      expect(rule.qualifyingCategories, contains('movies'));
      expect(rule.excludedCategories, contains('wallet_loads'));
    });

    test('validityStart/validityEnd accept real DateTime columns when present', () {
      final rule = MovieDealRule(
        benefitId: 'b3',
        catalogCardId: 'c3',
        title: 'Future-dated offer',
        offerType: MovieDealOfferType.percentDiscount,
        discountPercent: 20,
        validityStart: DateTime(2026, 1, 1),
        validityEnd: DateTime(2026, 12, 31),
      );

      expect(rule.validityStart, DateTime(2026, 1, 1));
      expect(rule.validityEnd, DateTime(2026, 12, 31));
    });
  });
}
