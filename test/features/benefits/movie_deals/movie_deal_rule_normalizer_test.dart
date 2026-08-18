// test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart';

MovieBenefitSource _source(
  Map<String, dynamic> config, {
  String? title,
  Set<String> partners = const {},
  Set<String> excludedCategories = const {},
}) => MovieBenefitSource(
  benefitId: 'b1',
  catalogCardId: 'c1',
  title: title ?? 'Test benefit',
  valueConfig: config,
  partners: partners,
  excludedCategories: excludedCategories,
);

void main() {
  group('normalizeMovieDealRule — percentDiscount', () {
    test(
      'discount_type=percent with discount_percent normalizes correctly',
      () {
        // Real row: "25% Off on Movie Tickets"
        final result = normalizeMovieDealRule(
          _source({'discount_type': 'percent', 'discount_percent': 25.0}),
        );
        expect(result, isA<AcceptedMovieDealRule>());
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.offerType, MovieDealOfferType.percentDiscount);
        expect(rule.discountPercent, 25.0);
        expect(rule.partners, isEmpty);
      },
    );

    test('partners column is carried through unchanged', () {
      // Real row: "Instant Discount on Bookmyshow" — partners: ["BookMyShow"]
      final result = normalizeMovieDealRule(
        _source(
          {
            'platform': 'Bookmyshow',
            'discount_type': 'percent',
            'discount_percent': 10.0,
          },
          partners: {'BookMyShow'},
        ),
      );
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.partners, contains('BookMyShow'));
      expect(rule.discountPercent, 10.0);
    });

    test('rejects a percentage outside 0-100', () {
      final result = normalizeMovieDealRule(
        _source({'discount_type': 'percent', 'discount_percent': 150.0}),
      );
      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });

    test(
      'max_discount_per_transaction normalizes to perTransactionCap when present',
      () {
        // Real rows carry this key on percent-type benefits too (e.g.
        // "10% Off on Tira Orders": max_discount_per_transaction: 1000.0,
        // "Fuel Surcharge Waiver": max_discount_per_transaction: 250.0) — the
        // normalizer previously only ever read this key for bogo, silently
        // dropping the cap for every capped percentDiscount row.
        final result = normalizeMovieDealRule(
          _source({
            'discount_type': 'percent',
            'discount_percent': 25.0,
            'max_discount_per_transaction': 100.0,
          }),
        );
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.perTransactionCap, 100.0);
      },
    );

    test(
      'perTransactionCap is null when max_discount_per_transaction is absent, never a fabricated 0',
      () {
        final result = normalizeMovieDealRule(
          _source({'discount_type': 'percent', 'discount_percent': 25.0}),
        );
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.perTransactionCap, isNull);
      },
    );
  });

  group('normalizeMovieDealRule — fixedDiscount', () {
    test(
      'monthly_cap normalizes to cycleAmountCap, never perTransactionCap',
      () {
        // Real row: "BookMyShow Discount" — monthly_cap: 1500.0 is a
        // TOTAL-FOR-THE-MONTH cap, not per-transaction (design spec §4.4).
        final result = normalizeMovieDealRule(
          _source(
            {
              'category': 'movie_tickets',
              'platform': 'BookMyShow',
              'monthly_cap': 1500.0,
              'is_recurring': true,
              'discount_amount': 1500.0,
            },
            partners: {'BookMyShow'},
          ),
        );
        expect(result, isA<AcceptedMovieDealRule>());
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.offerType, MovieDealOfferType.fixedDiscount);
        expect(rule.fixedAmount, 1500.0);
        expect(rule.cycleAmountCap, 1500.0);
        expect(rule.perTransactionCap, isNull);
      },
    );

    test('rejects a non-positive discount_amount', () {
      final result = normalizeMovieDealRule(_source({'discount_amount': 0}));
      expect(result, isA<RejectedMovieDealRule>());
    });
  });

  group('normalizeMovieDealRule — bogo', () {
    test(
      'max_discount_per_transaction normalizes to perTransactionCap, never cycleAmountCap',
      () {
        // Real row: "Twin ticket treats" — $500 off 2nd ticket (a SINGLE
        // redemption's cap), twice/month (a redemption COUNT, design spec §4.4).
        final result = normalizeMovieDealRule(
          _source(
            {
              'category': 'movie_tickets',
              'discount_type': 'BOGO',
              'max_usage_per_month': 2,
              'max_discount_per_transaction': 500.0,
            },
            title: 'Twin ticket treats',
            partners: {'Zomato'},
          ),
        );
        expect(result, isA<AcceptedMovieDealRule>());
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.offerType, MovieDealOfferType.bogo);
        expect(rule.buyCount, 1);
        expect(rule.freeCount, 1);
        expect(rule.perTransactionCap, 500.0);
        expect(rule.cycleRedemptionLimit, 2);
        expect(rule.cycleAmountCap, isNull);
        expect(rule.partners, contains('Zomato'));
      },
    );

    test(
      'second real bogo row (250 cap, no recorded partner) normalizes correctly',
      () {
        // Real row: "Buy-1-Get-1 Movie Ticket Offer" — partners: [] in the
        // real migration data (genuinely no partner recorded; do not invent one).
        final result = normalizeMovieDealRule(
          _source({
            'category': 'movie_tickets',
            'discount_type': 'BOGO',
            'max_usage_per_month': 2,
            'max_discount_per_transaction': 250.0,
          }),
        );
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.perTransactionCap, 250.0);
        expect(rule.cycleRedemptionLimit, 2);
        expect(rule.partners, isEmpty);
      },
    );

    test('quarterly BOGO limits retain their source period', () {
      final result = normalizeMovieDealRule(
        _source(
          {
            'category': 'movie_tickets',
            'discount_type': 'BOGO',
            'max_usage_per_period': 4,
            'usage_period': 'quarter',
            'max_discount_per_transaction': 500.0,
          },
          title: 'Zenith+ movie offer',
          partners: {'BookMyShow'},
        ),
      );

      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.cycleRedemptionLimit, 4);
      expect(rule.cyclePeriod, MovieDealCyclePeriod.quarter);
    });
  });

  group('normalizeMovieDealRule — never invents defaults', () {
    test('rejects a config with no derivable offer type', () {
      final result = normalizeMovieDealRule(
        _source({'category': 'movie_tickets'}),
      );
      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });
  });

  group('normalizeMovieDealRule — annualAllowance', () {
    test('unit=fixed with annual_cap and reward_value normalizes correctly', () {
      // Real row: "SBI Card ELITE Free Movie Tickets" — partners: [] (design spec §4.4).
      final result = normalizeMovieDealRule(
        _source({
          'unit': 'fixed',
          'category': 'movie_tickets',
          'annual_cap': 6000.0,
          'reward_value': 6000.0,
        }),
      );
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.annualAllowance);
      expect(rule.annualCap, 6000.0);
    });

    test('unit=fixed with only currency_unit normalizes correctly', () {
      // Real row: "Free Movie Tickets" (miscategorized as lifestyle)
      final result = normalizeMovieDealRule(
        _source({'unit': 'fixed', 'currency_unit': 6000.0}),
      );
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.annualAllowance);
      expect(rule.annualCap, 6000.0);
    });

    test('rejects unit=fixed with no amount field at all', () {
      final result = normalizeMovieDealRule(_source({'unit': 'fixed'}));
      expect(result, isA<RejectedMovieDealRule>());
    });
  });

  group('normalizeMovieDealRule — milestone', () {
    test(
      'reward_value + threshold_amount + milestone_type normalizes correctly, partners carried through',
      () {
        // Real row: "Monthly Vouchers on Spends" — partners: ["Uber",
        // "cult.fit Live", "BookMyShow", "TataCliQ"] (design spec §4.4).
        final result = normalizeMovieDealRule(
          _source(
            {
              'reward_value': 500.0,
              'milestone_type': 'monthly',
              'threshold_amount': 80000.0,
            },
            partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'},
          ),
        );
        expect(result, isA<AcceptedMovieDealRule>());
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.offerType, MovieDealOfferType.milestone);
        expect(rule.milestoneReward, 500.0);
        expect(rule.milestoneThreshold, 80000.0);
        expect(rule.partners, containsAll(['Uber', 'BookMyShow']));
      },
    );

    test('rejects a milestone missing threshold_amount', () {
      final result = normalizeMovieDealRule(
        _source({'reward_value': 500.0, 'milestone_type': 'monthly'}),
      );
      expect(result, isA<RejectedMovieDealRule>());
    });
  });

  group('normalizeMovieDealRule — rewardMultiplier', () {
    test(
      'points-per-rupee multiplier with movies in category list normalizes correctly',
      () {
        // Real row: "10X Reward Points on Dining, Movies, Departmental Stores and Grocery"
        final result = normalizeMovieDealRule(
          _source({
            'unit': 'points per Rs.150',
            'category': 'dining,movies,departmental_stores,grocery',
            'multiplier': 10.0,
          }),
        );
        expect(result, isA<AcceptedMovieDealRule>());
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
        expect(rule.rewardMultiplierRate, 10.0);
        expect(rule.rewardMultiplierUnit, 'points per Rs.150');
        expect(rule.qualifyingCategories, contains('movies'));
      },
    );

    test(
      'excludedCategories are carried through from the source, never parsed from valueConfig here',
      () {
        // Real row: "3% Cashpoints on Paytm Purchases" — exclusions.categories:
        // ["wallet_loads", "rent_payments", "government_payments"] — this is a
        // separate database column (design spec §4.2), parsed by the
        // repository (Tasks 10–11), not by this normalizer.
        final result = normalizeMovieDealRule(
          _source(
            {
              'unit': 'percent',
              'category': 'utilities,movies',
              'base_rate': 3.0,
              'is_recurring': true,
            },
            partners: {'Paytm'},
            excludedCategories: {
              'wallet_loads',
              'rent_payments',
              'government_payments',
            },
          ),
        );
        final rule = (result as AcceptedMovieDealRule).rule;
        expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
        expect(rule.rewardMultiplierRate, 3.0);
        expect(rule.excludedCategories, contains('wallet_loads'));
        expect(rule.partners, contains('Paytm'));
      },
    );

    test('rejects a category list with no movies entry', () {
      final result = normalizeMovieDealRule(
        _source({
          'unit': 'points per Rs.150',
          'category': 'dining,grocery',
          'multiplier': 10.0,
        }),
      );
      expect(result, isA<RejectedMovieDealRule>());
    });
  });
}
