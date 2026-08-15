// test/features/benefits/movie_deals/movie_benefit_fixture_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart';

MovieBenefitSource _source(
  Map<String, dynamic> config,
  String title, {
  Set<String> partners = const {},
  Set<String> excludedCategories = const {},
}) =>
    MovieBenefitSource(
      benefitId: 'fixture',
      catalogCardId: 'fixture-card',
      title: title,
      valueConfig: config,
      partners: partners,
      excludedCategories: excludedCategories,
    );

void main() {
  group('production-format fixture regression — every row matching the widened fetch (§4.1)', () {
    // Every value below is copied verbatim from a single real row in
    // supabase/migrations/20260711043900_restore_reference_data.sql —
    // none are invented (design spec §12). Named record fields (rather than
    // a positional tuple) so partners/excludedCategories — both Set<String>
    // — can never be silently transposed at a call site.
    final fixtures = <String, ({Map<String, dynamic> config, Set<String> partners, Set<String> excludedCategories, MovieDealOfferType expectedType})>{
      '25% Off on Movie Tickets': (
        config: {'discount_type': 'percent', 'discount_percent': 25.0},
        partners: {},
        excludedCategories: {},
        expectedType: MovieDealOfferType.percentDiscount,
      ),
      'SBI Card ELITE Free Movie Tickets': (
        config: {'unit': 'fixed', 'category': 'movie_tickets', 'annual_cap': 6000.0, 'reward_value': 6000.0},
        partners: {},
        excludedCategories: {},
        expectedType: MovieDealOfferType.annualAllowance,
      ),
      'Twin ticket treats': (
        config: {'category': 'movie_tickets', 'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 500.0},
        partners: {'Zomato'},
        excludedCategories: {},
        expectedType: MovieDealOfferType.bogo,
      ),
      'Buy-1-Get-1 Movie Ticket Offer': (
        config: {'category': 'movie_tickets', 'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 250.0},
        partners: {},
        excludedCategories: {},
        expectedType: MovieDealOfferType.bogo,
      ),
      'BookMyShow Discount': (
        config: {'category': 'movie_tickets', 'platform': 'BookMyShow', 'monthly_cap': 1500.0, 'is_recurring': true, 'currency_unit': 1500.0, 'discount_amount': 1500.0},
        partners: {'BookMyShow'},
        excludedCategories: {},
        expectedType: MovieDealOfferType.fixedDiscount,
      ),
      'Instant Discount on Bookmyshow': (
        config: {'category': 'movie_tickets', 'platform': 'Bookmyshow', 'discount_type': 'percent', 'discount_percent': 10.0},
        partners: {'BookMyShow'},
        excludedCategories: {},
        expectedType: MovieDealOfferType.percentDiscount,
      ),
      'Monthly Vouchers on Spends': (
        config: {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0},
        partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'},
        excludedCategories: {},
        expectedType: MovieDealOfferType.milestone,
      ),
      'Free Movie Tickets (lifestyle-tagged variant)': (
        config: {'unit': 'fixed', 'currency_unit': 6000.0},
        partners: {},
        excludedCategories: {},
        expectedType: MovieDealOfferType.annualAllowance,
      ),
      // Row 5e706c9f (seed data line 514) — the one real "10X Reward Points
      // on Dining, Movies, Departmental Stores and Grocery" variant that
      // carries excludedCategories data; category is spelled
      // "department_stores" (no "-al") on this specific row, unlike the
      // ~15 sibling rows sharing this title that use "departmental_stores"
      // and have no exclusions. An earlier version of this fixture blended
      // this row's excludedCategories with a different sibling row's
      // partners ({'Bank of Maharashtra'}) and category spelling — no real
      // row has both combined; corrected to match this single row exactly.
      '10X Reward Points on Dining, Movies, Departmental Stores and Grocery': (
        config: {'unit': 'points per Rs.150', 'category': 'dining,movies,department_stores,grocery', 'multiplier': 10.0},
        partners: {},
        excludedCategories: {'wallet_loads', 'rent_payments', 'fuel', 'insurance'},
        expectedType: MovieDealOfferType.rewardMultiplier,
      ),
      '3% Cashpoints on Paytm Purchases': (
        config: {'unit': 'percent', 'category': 'utilities,movies', 'base_rate': 3.0, 'monthly_cap': 500.0, 'is_recurring': true},
        partners: {'Paytm'},
        excludedCategories: {'wallet_loads', 'rent_payments', 'government_payments'},
        expectedType: MovieDealOfferType.rewardMultiplier,
      ),
      '5% Cashpoints on Paytm': (
        config: {'unit': 'percent', 'category': 'recharge,utilities,travel,movies', 'base_rate': 5.0, 'monthly_cap_points': 1500},
        partners: {'Paytm'},
        excludedCategories: {},
        expectedType: MovieDealOfferType.rewardMultiplier,
      ),
      // NOTE: a 4th row also titled "10X CashPoints on Favorite Merchants"
      // (category: "shopping,dining,entertainment") exists in the seed data
      // and was originally listed here, but its category value is
      // "entertainment", never the literal "movies"/"movie" token §4.4's
      // classification rule requires — it genuinely isn't a movie deal, and
      // normalizeMovieDealRule correctly rejects it. Removed per design spec
      // §4.4 correction (see docs/superpowers/specs/2026-08-02-movie-deals-design.md).
      // Do not re-add it; do not widen the classifier to treat "entertainment"
      // as movies-equivalent — no data supports that mapping.
    };

    fixtures.forEach((title, fixture) {
      test('$title normalizes as ${fixture.expectedType}', () {
        final result = normalizeMovieDealRule(
          _source(fixture.config, title, partners: fixture.partners, excludedCategories: fixture.excludedCategories),
        );
        expect(result, isA<AcceptedMovieDealRule>(),
            reason: 'Expected $title to be accepted, got: $result');
        expect((result as AcceptedMovieDealRule).rule.offerType, fixture.expectedType);
      });
    });
  });
}
