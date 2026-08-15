# Movie Deals Implementation Plan (v2 — rewritten against corrected design spec)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a "Movie Deals" screen recommending the best card a user owns and the best card overall for buying movie tickets, fully matching `docs/superpowers/specs/2026-08-02-movie-deals-design.md` (all four correction passes) — the four-tier `bestGuaranteed*`/`bestPotential*` result model, `eligibleMoviePlatforms`-based confidence (never raw `partners`), the `notRequested` confidence state with stated precedence, corrected migration ordering, and the widened milestone-cache query.

**Architecture:** Pure-Dart domain layer (rule model, normalizer, evaluator) with zero Flutter/Supabase dependency. A repository in `lib/core/repositories/` (matching this codebase's plain-`Provider`-class pattern — no Riverpod codegen) translates Supabase rows into domain input types, including a `moviePlatformAliases` registry as a checked-in constant. A `FutureProvider.family` drives search. A screen reuses the main repo's `MovieAnalyzerTab` form/card visual design, restructured for three result sections (Guaranteed, Potential, reward-multiplier-only).

**Tech Stack:** Flutter, Dart, Riverpod (plain `Provider`/`FutureProvider`), Supabase Flutter, `flutter_test`, `go_router`.

**Design doc:** `docs/superpowers/specs/2026-08-02-movie-deals-design.md` (supersedes the prior plan at `docs/superpowers/plans/2026-08-02-movie-deals.md`, which implements a stale pre-correction version of this design and must not be executed).

**Prerequisites gate (§3.1 of the design):** Tasks 1–6 (pure domain layer) have no database dependency and can proceed immediately. Task 7 (migrations) is the first task touching the database and implements §3.1's two P0 corrections directly — it is NOT gated on anything external; this plan resolves the P0s itself rather than waiting on prior action.

---

## File Map

| File | Responsibility |
|---|---|
| `lib/features/benefits/movie_deals/domain/movie_ticket_request.dart` | `MovieTicketRequest` input type |
| `lib/features/benefits/movie_deals/domain/movie_deal_rule.dart` | `MovieDealRule`, `MovieBenefitSource`, `MovieDealOfferType`, normalization result types |
| `lib/features/benefits/movie_deals/domain/movie_platform_aliases.dart` | `moviePlatformAliases` registry constant + `eligibleMoviePlatformsFor()` helper |
| `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart` | Raw `value_config`/`partners`/`exclusions` → `MovieDealRule` |
| `lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart` | `MovieDealCandidate`, confidence enums (incl. `notRequested`), `MovieDealsRecommendation` (4-field) |
| `lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart` | Eligibility, savings math, guaranteed/potential tier split |
| `lib/core/repositories/movie_deals_repository.dart` | Widened fetch (single `.or()`), per-benefit confirmation aggregation, milestone cycle-precise query |
| `lib/core/providers/repository_providers.dart` | Modify: add `movieDealsRepositoryProvider` |
| `lib/features/benefits/movie_deals/providers/movie_deals_provider.dart` | `FutureProvider.family` |
| `lib/features/benefits/movie_deals/screens/movie_deals_screen.dart` | Form (ported) |
| `lib/features/benefits/movie_deals/screens/movie_deals_results.dart` | 3-section results (Guaranteed / Potential / reward-rate-only) |
| `lib/core/router/app_router.dart` | Modify: 5th tab |
| `supabase/migrations/20260711043700_fix_benefit_column_types.sql` | **New** — resolves §3.1 P0 #2, timestamped between initial-schema and seed-data migrations |
| `supabase/migrations/20260802100000_curated_movie_benefit_mappings.sql` | **New** — resolves §3.1 P0 #1 + #3, curated (not mechanically restored) mappings |
| `supabase/migrations/20260802100100_benefit_platform_confirmations.sql` | **New** — §6 confirmation table with all integrity/security corrections |
| `test/features/benefits/movie_deals/*_test.dart` | Unit/widget tests per component |

---

## Task 1: `MovieTicketRequest` and the `MovieDealRule` canonical model

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_ticket_request.dart`
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_rule.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_rule_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/benefits/movie_deals/movie_deal_rule_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_test.dart`
Expected: FAIL — compile error, `movie_deal_rule.dart` does not exist yet.

- [ ] **Step 3: Write `movie_ticket_request.dart`**

```dart
// lib/features/benefits/movie_deals/domain/movie_ticket_request.dart

/// One search: how many tickets, at what price, on which platform/cinema.
/// Cinema is accepted and carried through but never filters or affects
/// confidence — design spec §1.1/§7 step 2: no real row carries cinema-chain
/// data, so every rule is currently cinema-agnostic. This is a stated,
/// deliberate gap, not an oversight.
class MovieTicketRequest {
  const MovieTicketRequest({
    required this.numberOfTickets,
    required this.pricePerTicket,
    this.preferredPlatform,
    this.preferredCinema,
  });

  final int numberOfTickets;
  final double pricePerTicket;
  final String? preferredPlatform;
  final String? preferredCinema;

  double get totalAmount => numberOfTickets * pricePerTicket;
}
```

- [ ] **Step 4: Write `movie_deal_rule.dart`**

```dart
// lib/features/benefits/movie_deals/domain/movie_deal_rule.dart

/// The benefit and card data required to normalize one movie-deal record.
/// [valueConfig] is the raw `benefits.value_config` JSONB. [partners] and
/// [exclusions] are the raw `benefits.partners`/`exclusions` JSONB columns —
/// separate database columns, not nested inside valueConfig (design spec §4.3).
class MovieBenefitSource {
  MovieBenefitSource({
    required this.benefitId,
    required this.catalogCardId,
    required this.title,
    required Map<String, dynamic> valueConfig,
    Set<String> partners = const {},
    Set<String> excludedCategories = const {},
    this.sourceUrl,
    this.cardName,
    this.displayPriority = 0,
    this.validityStart,
    this.validityEnd,
  })  : valueConfig = Map.unmodifiable(valueConfig),
        partners = Set.unmodifiable(partners),
        excludedCategories = Set.unmodifiable(excludedCategories);

  final String benefitId;
  final String catalogCardId;
  final String title;
  final Map<String, dynamic> valueConfig;
  final Set<String> partners;
  final Set<String> excludedCategories;
  final String? sourceUrl;
  final String? cardName;
  final int displayPriority;
  final DateTime? validityStart;
  final DateTime? validityEnd;
}

enum MovieDealOfferType {
  percentDiscount,
  fixedDiscount,
  bogo,
  annualAllowance,
  milestone,
  rewardMultiplier,
}

/// An immutable, validated movie-deal rule. Null commercial terms are
/// unknown, never inferred from a default (design spec §4.2/§4.4).
class MovieDealRule {
  MovieDealRule({
    required this.benefitId,
    required this.catalogCardId,
    required this.title,
    required this.offerType,
    this.sourceUrl,
    this.cardName,
    this.displayPriority = 0,
    Set<String> partners = const {},
    this.validityStart,
    this.validityEnd,
    this.discountPercent,
    this.fixedAmount,
    this.perTransactionCap,
    this.cycleAmountCap,
    this.buyCount,
    this.freeCount,
    this.cycleRedemptionLimit,
    this.annualCap,
    this.milestoneThreshold,
    this.milestoneReward,
    this.rewardMultiplierRate,
    this.rewardMultiplierUnit,
    Set<String> qualifyingCategories = const {},
    Set<String> excludedCategories = const {},
  })  : partners = Set.unmodifiable(partners),
        qualifyingCategories = Set.unmodifiable(qualifyingCategories),
        excludedCategories = Set.unmodifiable(excludedCategories);

  final String benefitId;
  final String catalogCardId;
  final String title;
  final String? sourceUrl;
  final String? cardName;
  final int displayPriority;
  final MovieDealOfferType offerType;

  /// Sourced from `benefits.partners` merged with `value_config.platform`
  /// when present (design spec §4.3). DISPLAY-ONLY — never read directly for
  /// eligibility or confidence (design spec §5/§7 correction). See
  /// `movie_platform_aliases.dart` for `eligibleMoviePlatformsFor(rule)`,
  /// the registry-filtered projection that eligibility/confidence actually use.
  final Set<String> partners;

  /// Sourced from `benefits.valid_from`/`valid_until` (real DB columns).
  /// Zero real entertainment rows populate them today — forward-compatible
  /// plumbing, not evidence the check is presently exercised (design spec §4.2).
  final DateTime? validityStart;
  final DateTime? validityEnd;

  final double? discountPercent;
  final double? fixedAmount;

  /// Caps a SINGLE booking's discount (e.g. bogo's per-pair cap, from
  /// `max_discount_per_transaction`). Distinct from [cycleAmountCap].
  final double? perTransactionCap;

  /// Caps TOTAL discount across the whole cycle (e.g. fixedDiscount's
  /// `monthly_cap`). Distinct from [perTransactionCap].
  final double? cycleAmountCap;

  /// bogo only. All real rows observed have buyCount=1, freeCount=1.
  final int? buyCount;
  final int? freeCount;

  /// "N redemptions/uses per cycle" — counts REDEMPTIONS, NOT tickets
  /// (design spec §4.4: `max_usage_per_month: 2` means 2 redemptions/month).
  final int? cycleRedemptionLimit;

  /// annualAllowance only — total ₹ available per calendar year.
  final double? annualCap;

  /// milestone only. Eligibility requires the PRIOR month's confirmed spend
  /// from `statement_milestone_cache` — but see the evaluator/repository for
  /// the category-level (not benefit-specific) precision limit (design spec §7).
  final double? milestoneThreshold;
  final double? milestoneReward;

  /// rewardMultiplier only. Never converted to a ₹ estimate — no
  /// points-to-rupee exchange rate exists in the data (design spec §7 step 6).
  final double? rewardMultiplierRate;
  final String? rewardMultiplierUnit;
  final Set<String> qualifyingCategories;

  /// rewardMultiplier only. Parsed from `exclusions.categories` — real data
  /// exists on 4 rewardMultiplier rows, never on any other offer type
  /// (design spec §4.2 correction).
  final Set<String> excludedCategories;
}

sealed class RuleNormalizationResult {
  const RuleNormalizationResult();
}

class AcceptedMovieDealRule extends RuleNormalizationResult {
  const AcceptedMovieDealRule(this.rule);
  final MovieDealRule rule;
}

class RejectedMovieDealRule extends RuleNormalizationResult {
  const RejectedMovieDealRule(this.reason);
  final String reason;
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_ticket_request.dart lib/features/benefits/movie_deals/domain/movie_deal_rule.dart test/features/benefits/movie_deals/movie_deal_rule_test.dart
git commit -m "feat: add MovieTicketRequest and MovieDealRule canonical model"
```

---

## Task 2: `moviePlatformAliases` registry and `eligibleMoviePlatformsFor()`

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_platform_aliases.dart`
- Test: `test/features/benefits/movie_deals/movie_platform_aliases_test.dart`

This is the design's core correction (§8, reconciled into §5): a checked-in registry, not an inferred derivation rule, so a multi-partner `milestone` row's non-movie partners are excluded deterministically.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/benefits/movie_deals/movie_platform_aliases_test.dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_platform_aliases_test.dart`
Expected: FAIL — compile error, `movie_platform_aliases.dart` does not exist yet.

- [ ] **Step 3: Write the registry**

```dart
// lib/features/benefits/movie_deals/domain/movie_platform_aliases.dart
import 'movie_deal_rule.dart';

/// Canonical movie-booking-platform vocabulary and alias map (design spec
/// §8). A CHECKED-IN CONSTANT, not derived at runtime from benefit data —
/// this is what makes a multi-partner milestone/rewardMultiplier row's
/// eligibleMoviePlatforms deterministic rather than left to inference.
/// Grow this map as new real movie-booking partners appear in future data.
const Map<String, String> moviePlatformAliases = {
  'bookmyshow': 'BookMyShow',
  'district': 'Zomato',
  'zomato': 'Zomato',
  'pvr': 'PVR',
  'inox': 'INOX',
  'cinepolis': 'Cinepolis',
  'moviemax': 'Moviemax',
};

String _normalize(String value) => value.trim().toLowerCase();

/// The movie-specific, registry-filtered projection of [rule.partners] —
/// THIS is what platform confidence (§5) and eligibility (§7) actually
/// check, never raw `rule.partners` directly. For a single-purpose offer
/// (percentDiscount/fixedDiscount/bogo) this equals partners verbatim
/// (mapped through the alias table). For a multi-partner milestone/
/// rewardMultiplier row, this is the intersection with the registry —
/// non-movie partners (Uber, cult.fit Live, Big Basket, OYO, Swiggy) are
/// never included, regardless of how many partners the raw benefit lists.
Set<String> eligibleMoviePlatformsFor(MovieDealRule rule) {
  final result = <String>{};
  for (final partner in rule.partners) {
    final canonical = moviePlatformAliases[_normalize(partner)];
    if (canonical != null) result.add(canonical);
  }
  return result;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_platform_aliases_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_platform_aliases.dart test/features/benefits/movie_deals/movie_platform_aliases_test.dart
git commit -m "feat: add moviePlatformAliases registry and eligibleMoviePlatformsFor"
```

---

## Task 3: Normalizer — percentDiscount, fixedDiscount, bogo

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`

`MovieBenefitSource.partners`/`.excludedCategories` are separate database-column inputs, not parsed from `valueConfig` — the normalizer only reads `valueConfig` for offer-type-specific numeric/string fields and passes `partners`/`excludedCategories` through unchanged (they arrive pre-parsed from the repository, Tasks 10–11).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart';

MovieBenefitSource _source(
  Map<String, dynamic> config, {
  String? title,
  Set<String> partners = const {},
  Set<String> excludedCategories = const {},
}) =>
    MovieBenefitSource(
      benefitId: 'b1',
      catalogCardId: 'c1',
      title: title ?? 'Test benefit',
      valueConfig: config,
      partners: partners,
      excludedCategories: excludedCategories,
    );

void main() {
  group('normalizeMovieDealRule — percentDiscount', () {
    test('discount_type=percent with discount_percent normalizes correctly', () {
      // Real row: "25% Off on Movie Tickets"
      final result = normalizeMovieDealRule(
        _source({'discount_type': 'percent', 'discount_percent': 25.0}),
      );
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.percentDiscount);
      expect(rule.discountPercent, 25.0);
      expect(rule.partners, isEmpty);
    });

    test('partners column is carried through unchanged', () {
      // Real row: "Instant Discount on Bookmyshow" — partners: ["BookMyShow"]
      final result = normalizeMovieDealRule(_source(
        {'platform': 'Bookmyshow', 'discount_type': 'percent', 'discount_percent': 10.0},
        partners: {'BookMyShow'},
      ));
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
  });

  group('normalizeMovieDealRule — fixedDiscount', () {
    test('monthly_cap normalizes to cycleAmountCap, never perTransactionCap', () {
      // Real row: "BookMyShow Discount" — monthly_cap: 1500.0 is a
      // TOTAL-FOR-THE-MONTH cap, not per-transaction (design spec §4.4).
      final result = normalizeMovieDealRule(_source(
        {'category': 'movie_tickets', 'platform': 'BookMyShow', 'monthly_cap': 1500.0,
         'is_recurring': true, 'discount_amount': 1500.0},
        partners: {'BookMyShow'},
      ));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.fixedDiscount);
      expect(rule.fixedAmount, 1500.0);
      expect(rule.cycleAmountCap, 1500.0);
      expect(rule.perTransactionCap, isNull);
    });

    test('rejects a non-positive discount_amount', () {
      final result = normalizeMovieDealRule(_source({'discount_amount': 0}));
      expect(result, isA<RejectedMovieDealRule>());
    });
  });

  group('normalizeMovieDealRule — bogo', () {
    test('max_discount_per_transaction normalizes to perTransactionCap, never cycleAmountCap', () {
      // Real row: "Twin ticket treats" — $500 off 2nd ticket (a SINGLE
      // redemption's cap), twice/month (a redemption COUNT, design spec §4.4).
      final result = normalizeMovieDealRule(_source({
        'category': 'movie_tickets',
        'discount_type': 'BOGO',
        'max_usage_per_month': 2,
        'max_discount_per_transaction': 500.0,
      }, title: 'Twin ticket treats', partners: {'Zomato'}));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.bogo);
      expect(rule.buyCount, 1);
      expect(rule.freeCount, 1);
      expect(rule.perTransactionCap, 500.0);
      expect(rule.cycleRedemptionLimit, 2);
      expect(rule.cycleAmountCap, isNull);
      expect(rule.partners, contains('Zomato'));
    });

    test('second real bogo row (250 cap, no recorded partner) normalizes correctly', () {
      // Real row: "Buy-1-Get-1 Movie Ticket Offer" — partners: [] in the
      // real migration data (genuinely no partner recorded; do not invent one).
      final result = normalizeMovieDealRule(_source({
        'category': 'movie_tickets',
        'discount_type': 'BOGO',
        'max_usage_per_month': 2,
        'max_discount_per_transaction': 250.0,
      }));
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.perTransactionCap, 250.0);
      expect(rule.cycleRedemptionLimit, 2);
      expect(rule.partners, isEmpty);
    });
  });

  group('normalizeMovieDealRule — never invents defaults', () {
    test('rejects a config with no derivable offer type', () {
      final result = normalizeMovieDealRule(_source({'category': 'movie_tickets'}));
      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`
Expected: FAIL — compile error, `movie_deal_rule_normalizer.dart` and `normalizeMovieDealRule` don't exist yet.

- [ ] **Step 3: Write the normalizer**

```dart
// lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart
import 'movie_deal_rule.dart';

/// Normalizes real benefits.value_config shapes into a MovieDealRule.
/// Every branch is derived from an actual row observed in
/// supabase/migrations/20260711043900_restore_reference_data.sql — see
/// design spec §4.4 for the full field-alias table. Unrecognized or
/// contradictory shapes are rejected with a diagnostic reason; nothing is
/// ever defaulted or invented. partners/excludedCategories are separate
/// database columns passed through from MovieBenefitSource unchanged —
/// this normalizer never parses them out of valueConfig.
RuleNormalizationResult normalizeMovieDealRule(MovieBenefitSource source) {
  final config = source.valueConfig;

  final discountType = _string(config['discount_type'])?.toLowerCase();
  if (discountType == 'bogo') {
    return _normalizeBogo(source);
  }

  final discountPercent = _number(config['discount_percent']);
  if (discountType == 'percent' || discountPercent != null) {
    return _normalizePercent(source, discountPercent);
  }

  // rawUnit preserves the original casing for storage/display
  // (rewardMultiplierUnit, e.g. "points per Rs.150" must survive intact —
  // a real bug found during implementation: an earlier draft only kept the
  // lowercased comparison value and passed THAT into storage, silently
  // lowercasing every displayed unit string). unit (lowercased) is used
  // ONLY for the dispatch comparisons below (`unit != 'fixed'` etc.).
  final rawUnit = _string(config['unit']);
  final unit = rawUnit?.toLowerCase();
  final threshold = _number(config['threshold_amount']);
  final milestoneType = _string(config['milestone_type']);
  if (milestoneType != null || threshold != null) {
    return _normalizeMilestone(source);
  }

  final category = _string(config['category'])?.toLowerCase() ?? '';
  final mentionsMovies = category.split(',').map((c) => c.trim()).contains('movies');
  final rate = _number(config['multiplier']) ?? _number(config['base_rate']);
  if (mentionsMovies && rate != null && rawUnit != null && unit != 'fixed') {
    return _normalizeRewardMultiplier(source, rawUnit, rate, category);
  }

  if (unit == 'fixed') {
    final amount = _number(config['annual_cap']) ??
        _number(config['reward_value']) ??
        _number(config['currency_unit']);
    if (amount != null) {
      return _normalizeAnnualAllowance(source, amount);
    }
    return const RejectedMovieDealRule(
      'A fixed annual allowance requires annual_cap, reward_value, or currency_unit.',
    );
  }

  final discountAmount = _number(config['discount_amount']);
  if (discountAmount != null) {
    return _normalizeFixed(source, discountAmount);
  }

  return const RejectedMovieDealRule(
    'No unambiguous movie offer type was supplied.',
  );
}

RuleNormalizationResult _normalizePercent(
  MovieBenefitSource source,
  double? discountPercent,
) {
  if (discountPercent == null || discountPercent <= 0 || discountPercent > 100) {
    return const RejectedMovieDealRule(
      'A percentage offer requires a rate between 0 and 100.',
    );
  }
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    validityStart: source.validityStart,
    validityEnd: source.validityEnd,
    offerType: MovieDealOfferType.percentDiscount,
    partners: source.partners,
    discountPercent: discountPercent,
  ));
}

RuleNormalizationResult _normalizeFixed(
  MovieBenefitSource source,
  double discountAmount,
) {
  if (discountAmount <= 0) {
    return const RejectedMovieDealRule(
      'A fixed-value offer requires a positive discount amount.',
    );
  }
  // monthly_cap is a TOTAL-for-the-cycle cap, never a per-transaction one
  // (design spec §4.4) — fixedDiscount only ever populates cycleAmountCap.
  final cycleCap = _number(source.valueConfig['monthly_cap']);
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    validityStart: source.validityStart,
    validityEnd: source.validityEnd,
    offerType: MovieDealOfferType.fixedDiscount,
    partners: source.partners,
    fixedAmount: discountAmount,
    cycleAmountCap: cycleCap,
  ));
}

RuleNormalizationResult _normalizeBogo(MovieBenefitSource source) {
  // max_discount_per_transaction caps a SINGLE redemption — perTransactionCap,
  // never cycleAmountCap. max_usage_per_month counts REDEMPTIONS, never
  // tickets (design spec §4.4).
  final perTxnCap = _number(source.valueConfig['max_discount_per_transaction']);
  final cycleLimit = _integer(source.valueConfig['max_usage_per_month']);
  if (perTxnCap == null || perTxnCap <= 0) {
    return const RejectedMovieDealRule(
      'A BOGO offer requires a positive per-transaction discount cap.',
    );
  }
  if (cycleLimit == null || cycleLimit <= 0) {
    return const RejectedMovieDealRule(
      'A BOGO offer requires a positive monthly redemption limit.',
    );
  }
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    validityStart: source.validityStart,
    validityEnd: source.validityEnd,
    offerType: MovieDealOfferType.bogo,
    partners: source.partners,
    buyCount: 1,
    freeCount: 1,
    perTransactionCap: perTxnCap,
    cycleRedemptionLimit: cycleLimit,
  ));
}

double? _number(Object? value) {
  final number = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  return number?.isFinite ?? false ? number : null;
}

int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
```

Leave `_normalizeMilestone`, `_normalizeAnnualAllowance`, `_normalizeRewardMultiplier` as forward references — Task 4 adds them to this same file.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`
Expected: FAIL still — `_normalizeMilestone` etc. are referenced in the dispatch but not yet defined. This is expected; Task 4 completes the file. Confirm the failure is specifically an undefined-function compile error, not a logic failure in the branches written so far.

- [ ] **Step 5: Commit is deferred to Task 4**

This file does not compile standalone yet. Proceed directly to Task 4; both tasks' code commits together there.

---

## Task 4: Normalizer — annualAllowance, milestone, rewardMultiplier (completes the file)

**Files:**
- Modify: `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart` (append the three missing functions)
- Modify: `test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart` (append tests)

- [ ] **Step 1: Add the failing tests**

Append to `test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`, inside `main()`:

```dart
  group('normalizeMovieDealRule — annualAllowance', () {
    test('unit=fixed with annual_cap and reward_value normalizes correctly', () {
      // Real row: "SBI Card ELITE Free Movie Tickets" — partners: [] (design spec §4.4).
      final result = normalizeMovieDealRule(_source({
        'unit': 'fixed',
        'category': 'movie_tickets',
        'annual_cap': 6000.0,
        'reward_value': 6000.0,
      }));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.annualAllowance);
      expect(rule.annualCap, 6000.0);
    });

    test('unit=fixed with only currency_unit normalizes correctly', () {
      // Real row: "Free Movie Tickets" (miscategorized as lifestyle)
      final result = normalizeMovieDealRule(_source({
        'unit': 'fixed',
        'currency_unit': 6000.0,
      }));
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
    test('reward_value + threshold_amount + milestone_type normalizes correctly, partners carried through', () {
      // Real row: "Monthly Vouchers on Spends" — partners: ["Uber",
      // "cult.fit Live", "BookMyShow", "TataCliQ"] (design spec §4.4).
      final result = normalizeMovieDealRule(_source(
        {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0},
        partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'},
      ));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.milestone);
      expect(rule.milestoneReward, 500.0);
      expect(rule.milestoneThreshold, 80000.0);
      expect(rule.partners, containsAll(['Uber', 'BookMyShow']));
    });

    test('rejects a milestone missing threshold_amount', () {
      final result = normalizeMovieDealRule(_source({
        'reward_value': 500.0,
        'milestone_type': 'monthly',
      }));
      expect(result, isA<RejectedMovieDealRule>());
    });
  });

  group('normalizeMovieDealRule — rewardMultiplier', () {
    test('points-per-rupee multiplier with movies in category list normalizes correctly', () {
      // Real row: "10X Reward Points on Dining, Movies, Departmental Stores and Grocery"
      final result = normalizeMovieDealRule(_source({
        'unit': 'points per Rs.150',
        'category': 'dining,movies,departmental_stores,grocery',
        'multiplier': 10.0,
      }));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
      expect(rule.rewardMultiplierRate, 10.0);
      expect(rule.rewardMultiplierUnit, 'points per Rs.150');
      expect(rule.qualifyingCategories, contains('movies'));
    });

    test('excludedCategories are carried through from the source, never parsed from valueConfig here', () {
      // Real row: "3% Cashpoints on Paytm Purchases" — exclusions.categories:
      // ["wallet_loads", "rent_payments", "government_payments"] — this is a
      // separate database column (design spec §4.2), parsed by the
      // repository (Tasks 10–11), not by this normalizer.
      final result = normalizeMovieDealRule(_source(
        {'unit': 'percent', 'category': 'utilities,movies', 'base_rate': 3.0, 'is_recurring': true},
        partners: {'Paytm'},
        excludedCategories: {'wallet_loads', 'rent_payments', 'government_payments'},
      ));
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
      expect(rule.rewardMultiplierRate, 3.0);
      expect(rule.excludedCategories, contains('wallet_loads'));
      expect(rule.partners, contains('Paytm'));
    });

    test('rejects a category list with no movies entry', () {
      final result = normalizeMovieDealRule(_source({
        'unit': 'points per Rs.150',
        'category': 'dining,grocery',
        'multiplier': 10.0,
      }));
      expect(result, isA<RejectedMovieDealRule>());
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`
Expected: FAIL — the new tests expect `MovieDealOfferType.annualAllowance`/`.milestone`/`.rewardMultiplier` branches the dispatch doesn't yet reach (falls through to "no unambiguous offer type").

- [ ] **Step 3: Append the three normalizer functions**

Add to the end of `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart` (after `_normalizeBogo`, before the `_number`/`_integer`/`_string` helpers):

```dart
RuleNormalizationResult _normalizeAnnualAllowance(
  MovieBenefitSource source,
  double annualCap,
) {
  if (annualCap <= 0) {
    return const RejectedMovieDealRule(
      'An annual allowance requires a positive amount.',
    );
  }
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    validityStart: source.validityStart,
    validityEnd: source.validityEnd,
    offerType: MovieDealOfferType.annualAllowance,
    partners: source.partners,
    annualCap: annualCap,
  ));
}

RuleNormalizationResult _normalizeMilestone(MovieBenefitSource source) {
  final threshold = _number(source.valueConfig['threshold_amount']);
  final reward = _number(source.valueConfig['reward_value']);
  if (threshold == null || reward == null) {
    return const RejectedMovieDealRule(
      'A milestone requires both a threshold and reward.',
    );
  }
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    validityStart: source.validityStart,
    validityEnd: source.validityEnd,
    offerType: MovieDealOfferType.milestone,
    partners: source.partners,
    milestoneThreshold: threshold,
    milestoneReward: reward,
  ));
}

RuleNormalizationResult _normalizeRewardMultiplier(
  MovieBenefitSource source,
  String unit,
  double rate,
  String category,
) {
  if (rate <= 0) {
    return const RejectedMovieDealRule(
      'A reward multiplier requires a positive rate.',
    );
  }
  final categories = category
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toSet();
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    validityStart: source.validityStart,
    validityEnd: source.validityEnd,
    offerType: MovieDealOfferType.rewardMultiplier,
    partners: source.partners,
    rewardMultiplierRate: rate,
    rewardMultiplierUnit: unit,
    qualifyingCategories: categories,
    excludedCategories: source.excludedCategories,
  ));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`
Expected: PASS (17 tests total)

- [ ] **Step 5: Commit both Task 3 and Task 4 files together**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart
git commit -m "feat: normalize all 6 movie deal offer types with corrected cap/partner sourcing"
```

---

## Task 5: Fixture regression test against every real seed-data row

**Files:**
- Test: `test/features/benefits/movie_deals/movie_benefit_fixture_test.dart`

Design spec §12 requires every row in the widened fetch's candidate set to be covered, not a representative sample — this is the regression guard against silently mis-normalizing a new or unanticipated real row.

- [ ] **Step 1: Write the test**

```dart
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
    // Each entry: (config, partners, excludedCategories, expectedType).
    // Every value below is copied verbatim from
    // supabase/migrations/20260711043900_restore_reference_data.sql —
    // none are invented (design spec §12).
    final fixtures = <String, (Map<String, dynamic>, Set<String>, Set<String>, MovieDealOfferType)>{
      '25% Off on Movie Tickets': (
        {'discount_type': 'percent', 'discount_percent': 25.0},
        {}, {}, MovieDealOfferType.percentDiscount,
      ),
      'SBI Card ELITE Free Movie Tickets': (
        {'unit': 'fixed', 'category': 'movie_tickets', 'annual_cap': 6000.0, 'reward_value': 6000.0},
        {}, {}, MovieDealOfferType.annualAllowance,
      ),
      'Twin ticket treats': (
        {'category': 'movie_tickets', 'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 500.0},
        {'Zomato'}, {}, MovieDealOfferType.bogo,
      ),
      'Buy-1-Get-1 Movie Ticket Offer': (
        {'category': 'movie_tickets', 'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 250.0},
        {}, {}, MovieDealOfferType.bogo,
      ),
      'BookMyShow Discount': (
        {'category': 'movie_tickets', 'platform': 'BookMyShow', 'monthly_cap': 1500.0, 'is_recurring': true, 'currency_unit': 1500.0, 'discount_amount': 1500.0},
        {'BookMyShow'}, {}, MovieDealOfferType.fixedDiscount,
      ),
      'Instant Discount on Bookmyshow': (
        {'category': 'movie_tickets', 'platform': 'Bookmyshow', 'discount_type': 'percent', 'discount_percent': 10.0},
        {'BookMyShow'}, {}, MovieDealOfferType.percentDiscount,
      ),
      'Monthly Vouchers on Spends': (
        {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0},
        {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'}, {}, MovieDealOfferType.milestone,
      ),
      'Free Movie Tickets (lifestyle-tagged variant)': (
        {'unit': 'fixed', 'currency_unit': 6000.0},
        {}, {}, MovieDealOfferType.annualAllowance,
      ),
      '10X Reward Points on Dining, Movies, Departmental Stores and Grocery': (
        {'unit': 'points per Rs.150', 'category': 'dining,movies,departmental_stores,grocery', 'multiplier': 10.0},
        {'Bank of Maharashtra'}, {'wallet_loads', 'rent_payments', 'fuel', 'insurance'}, MovieDealOfferType.rewardMultiplier,
      ),
      '3% Cashpoints on Paytm Purchases': (
        {'unit': 'percent', 'category': 'utilities,movies', 'base_rate': 3.0, 'monthly_cap': 500.0, 'is_recurring': true},
        {'Paytm'}, {'wallet_loads', 'rent_payments', 'government_payments'}, MovieDealOfferType.rewardMultiplier,
      ),
      '5% Cashpoints on Paytm': (
        {'unit': 'percent', 'category': 'recharge,utilities,travel,movies', 'base_rate': 5.0, 'monthly_cap_points': 1500},
        {'Paytm'}, {}, MovieDealOfferType.rewardMultiplier,
      ),
      // NOTE: a 4th row also titled "10X CashPoints on Favorite Merchants"
      // (category: "shopping,dining,entertainment") exists in the seed data
      // and was originally listed here, but its category value is
      // "entertainment", never the literal "movies"/"movie" token §4.4's
      // classification rule requires — it genuinely isn't a movie deal, and
      // normalizeMovieDealRule correctly rejects it. Removed per design spec
      // §4.4 correction (see spec file). Do not re-add it; do not widen the
      // classifier to treat "entertainment" as movies-equivalent — no data
      // supports that mapping.
    };

    fixtures.forEach((title, fixture) {
      final (config, partners, excluded, expectedType) = fixture;
      test('$title normalizes as $expectedType', () {
        final result = normalizeMovieDealRule(
          _source(config, title, partners: partners, excludedCategories: excluded),
        );
        expect(result, isA<AcceptedMovieDealRule>(),
            reason: 'Expected $title to be accepted, got: $result');
        expect((result as AcceptedMovieDealRule).rule.offerType, expectedType);
      });
    });

    test('a row with movies in category but no rate is rejected, not silently dropped', () {
      final result = normalizeMovieDealRule(_source(
        {'category': 'movie_tickets'},
        'Ambiguous row',
      ));
      expect(result, isA<RejectedMovieDealRule>());
      expect((result as RejectedMovieDealRule).reason, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_benefit_fixture_test.dart`
Expected: If Tasks 3–4 were completed correctly, this should already PASS (12 tests) — it's a regression guard over existing behavior. Run it to confirm.

- [ ] **Step 3: If any fixture fails, fix the normalizer, never the fixture**

A fixture mismatch means a real production row would be mishandled. Trace which branch of `normalizeMovieDealRule` the failing config falls into and fix that branch — do not adjust the expected value to match broken behavior.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_benefit_fixture_test.dart`
Expected: PASS (12 tests)

- [ ] **Step 5: Commit**

```bash
git add test/features/benefits/movie_deals/movie_benefit_fixture_test.dart
git commit -m "test: add production-format fixture regression for movie deal normalizer"
```

---

## Task 6: Candidate/recommendation models — 4-state confidence, 4-field result split

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_candidate_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/benefits/movie_deals/movie_deal_candidate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';

MovieDealCandidate _candidate({
  required String cardId,
  required bool isOwned,
  MovieDealUsageConfidence usageConfidence = MovieDealUsageConfidence.unverified,
  MovieDealPlatformConfidence platformConfidence = MovieDealPlatformConfidence.explicit,
}) {
  final rule = MovieDealRule(
    benefitId: 'b-$cardId',
    catalogCardId: cardId,
    title: 'Test',
    offerType: MovieDealOfferType.percentDiscount,
    discountPercent: 25,
  );
  return MovieDealCandidate(
    cardId: cardId,
    benefitId: 'b-$cardId',
    title: 'Test',
    rule: rule,
    isOwned: isOwned,
    grossAmount: 1000,
    savings: 250,
    finalAmount: 750,
    usageConfidence: usageConfidence,
    platformConfidence: platformConfidence,
    explanation: 'saves 250',
  );
}

void main() {
  test('MovieDealsRecommendation exposes 4 independent best-candidate fields', () {
    final guaranteedOwned = _candidate(cardId: 'owned-guaranteed', isOwned: true);
    final potentialOverall = _candidate(
      cardId: 'unowned-potential',
      isOwned: false,
      usageConfidence: MovieDealUsageConfidence.unverified,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [guaranteedOwned, potentialOverall],
      rejectedCandidates: const [],
      bestGuaranteedOwned: guaranteedOwned,
      bestGuaranteedOverall: guaranteedOwned,
      bestPotentialOwned: null,
      bestPotentialOverall: potentialOverall,
    );

    expect(recommendation.bestGuaranteedOwned, guaranteedOwned);
    expect(recommendation.bestGuaranteedOverall, guaranteedOwned);
    expect(recommendation.bestPotentialOwned, isNull);
    expect(recommendation.bestPotentialOverall, potentialOverall);
    expect(recommendation.status, MovieDealsStatus.available);
  });

  test('unavailable status can be constructed without any of the four winner fields', () {
    const recommendation = MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );
    expect(recommendation.bestGuaranteedOwned, isNull);
    expect(recommendation.bestGuaranteedOverall, isNull);
    expect(recommendation.bestPotentialOwned, isNull);
    expect(recommendation.bestPotentialOverall, isNull);
  });

  test('MovieDealPlatformConfidence has 4 distinct states including notRequested', () {
    expect(MovieDealPlatformConfidence.values, hasLength(4));
    expect(MovieDealPlatformConfidence.values, contains(MovieDealPlatformConfidence.explicit));
    expect(MovieDealPlatformConfidence.values, contains(MovieDealPlatformConfidence.communityConfirmed));
    expect(MovieDealPlatformConfidence.values, contains(MovieDealPlatformConfidence.unconfirmed));
    expect(MovieDealPlatformConfidence.values, contains(MovieDealPlatformConfidence.notRequested));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_candidate_test.dart`
Expected: FAIL — compile error, file doesn't exist.

- [ ] **Step 3: Write `movie_deal_candidate.dart`**

```dart
// lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart
import 'movie_deal_rule.dart';

enum MovieDealUsageConfidence { verified, unverified, unavailable }

/// Design spec §5 (with the notRequested correction). Computed per
/// evaluation from rule.eligibleMoviePlatforms — NEVER from raw rule.partners
/// — depends on both the rule and the specific platform searched for.
enum MovieDealPlatformConfidence {
  /// eligibleMoviePlatforms is non-empty and contains the searched platform,
  /// OR the search was unconstrained ("Any Platform") and eligibleMoviePlatforms
  /// is non-empty.
  explicit,

  /// eligibleMoviePlatforms is empty, but >=1 confirmed user report exists
  /// for the searched platform (or, under "Any Platform," for ANY platform
  /// on this benefit) — takes precedence over notRequested whenever a
  /// confirmation exists (design spec §5 precedence correction).
  communityConfirmed,

  /// eligibleMoviePlatforms is empty, no confirmations exist, and a SPECIFIC
  /// platform was requested (not "Any Platform").
  unconfirmed,

  /// The search was unconstrained ("Any Platform"), eligibleMoviePlatforms is
  /// empty, AND no confirmations exist for this benefit under any platform.
  /// Distinct from unconfirmed: does not imply anyone tried and failed to
  /// establish the platform — the question was simply never asked. Never
  /// qualifies for the guaranteed tier (design spec §5).
  notRequested,
}

enum MovieDealsStatus { available, unavailable }

/// Context supplied by the repository for one catalog card's ONE benefit —
/// keyed by (catalogCardId, benefitId), never catalogCardId alone (design
/// spec §5 confirmation-scoping correction), to prevent a confirmation on
/// one benefit leaking onto a different benefit sharing the same card.
class MovieDealContext {
  const MovieDealContext({
    this.isOwned = false,
    this.usageConfidence = MovieDealUsageConfidence.unverified,
    this.usedTickets = 0,
    this.usedTransactions = 0,
    this.milestoneSpend,
    this.confirmedPlatforms = const {},
  });

  final bool isOwned;
  final MovieDealUsageConfidence usageConfidence;
  final int usedTickets;
  final int usedTransactions;
  final double? milestoneSpend;

  /// Platforms with >=1 confirmation for THIS SPECIFIC benefitId
  /// (design spec §6/§5) — never a card-wide union across benefits.
  final Set<String> confirmedPlatforms;
}

class MovieDealCandidate {
  const MovieDealCandidate({
    required this.cardId,
    required this.benefitId,
    required this.title,
    required this.rule,
    required this.isOwned,
    required this.grossAmount,
    required this.savings,
    required this.finalAmount,
    required this.usageConfidence,
    required this.platformConfidence,
    required this.explanation,
    this.remainingVerifiedUsage,
  });

  final String cardId;
  final String benefitId;
  final String title;
  final MovieDealRule rule;
  final bool isOwned;
  final double grossAmount;
  final double savings;
  final double finalAmount;
  final MovieDealUsageConfidence usageConfidence;
  final MovieDealPlatformConfidence platformConfidence;
  final int? remainingVerifiedUsage;
  final String explanation;
}

class RejectedMovieDealCandidate {
  const RejectedMovieDealCandidate({
    required this.cardId,
    required this.benefitId,
    required this.rule,
    required this.reason,
  });

  final String cardId;
  final String benefitId;
  final MovieDealRule rule;
  final String reason;
}

/// Design spec §5 correction: 4 explicit fields, not 2 untyped ones — a
/// potential-tier result can never be assigned to a bestGuaranteed* field,
/// because the type itself keeps the tiers separate. No comment-enforced
/// convention for the UI to remember; the split is structural.
class MovieDealsRecommendation {
  const MovieDealsRecommendation({
    required this.candidates,
    required this.rejectedCandidates,
    this.status = MovieDealsStatus.available,
    this.bestGuaranteedOwned,
    this.bestGuaranteedOverall,
    this.bestPotentialOwned,
    this.bestPotentialOverall,
  });

  final List<MovieDealCandidate> candidates;
  final List<RejectedMovieDealCandidate> rejectedCandidates;
  final MovieDealsStatus status;
  final MovieDealCandidate? bestGuaranteedOwned;
  final MovieDealCandidate? bestGuaranteedOverall;
  final MovieDealCandidate? bestPotentialOwned;
  final MovieDealCandidate? bestPotentialOverall;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_candidate_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart test/features/benefits/movie_deals/movie_deal_candidate_test.dart
git commit -m "feat: add 4-state platform confidence and 4-field guaranteed/potential result split"
```

---

## Task 7: Evaluator — eligibility, savings math, guaranteed/potential tier split

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_evaluator_test.dart`

This is the most involved task. It implements design spec §5's corrected gate precisely: guaranteed tier requires `usageConfidence == verified` (or an uncapped `percentDiscount`/`bogo`) AND `platformConfidence == explicit` — computed from `eligibleMoviePlatforms`, never raw `partners`. Per §7's stated data-availability limit, `usageConfidence` can never reach `verified` for `bogo`, `fixedDiscount` with a `cycleAmountCap`, or `milestone` — so in the current data state, only `percentDiscount` can populate the guaranteed tier. This is not special-cased in the code; it falls out naturally from `usageConfidence` legitimately never being `verified` for those types (no real signal exists to set it).

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_evaluator.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';

MovieDealRule _bogoRule({String cardId = 'c1', Set<String> partners = const {}}) => MovieDealRule(
      benefitId: 'b-bogo',
      catalogCardId: cardId,
      title: 'Twin ticket treats',
      offerType: MovieDealOfferType.bogo,
      partners: partners,
      buyCount: 1,
      freeCount: 1,
      perTransactionCap: 500,
      cycleRedemptionLimit: 2,
    );

MovieDealRule _percentRule({String cardId = 'c2', double percent = 10, Set<String> partners = const {}}) =>
    MovieDealRule(
      benefitId: 'b-percent',
      catalogCardId: cardId,
      title: '10% off',
      offerType: MovieDealOfferType.percentDiscount,
      discountPercent: percent,
      partners: partners,
    );

MovieDealRule _milestoneRule({String cardId = 'c3', Set<String> partners = const {}}) => MovieDealRule(
      benefitId: 'b-milestone',
      catalogCardId: cardId,
      title: 'Monthly Vouchers',
      offerType: MovieDealOfferType.milestone,
      milestoneThreshold: 80000,
      milestoneReward: 500,
      partners: partners,
    );

MovieDealRule _fixedDiscountWithCapRule({String cardId = 'c4'}) => MovieDealRule(
      benefitId: 'b-fixed',
      catalogCardId: cardId,
      title: 'BookMyShow Discount',
      offerType: MovieDealOfferType.fixedDiscount,
      fixedAmount: 1500,
      cycleAmountCap: 1500,
      partners: const {'BookMyShow'},
    );

void main() {
  final today = DateTime(2026, 8, 2);

  group('bogo savings math', () {
    test('per-transaction cap of 500 clamps a lower-priced pair to the full ticket price', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 400),
        rules: [_bogoRule()],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, 400);
      expect(candidate.finalAmount, 400);
    });

    test('per-transaction cap of 500 clamps when the second ticket exceeds the cap', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 600),
        rules: [_bogoRule()],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, 500);
      expect(candidate.finalAmount, 700);
    });
  });

  group('percentDiscount savings math', () {
    test('4 tickets at 300 with 10% off saves 120', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300),
        rules: [_percentRule(percent: 10)],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.savings, 120);
      expect(candidate.finalAmount, 1080);
    });
  });

  group('guaranteed-tier gate — data-availability limit (design spec §5/§7)', () {
    test('a bogo candidate with verified-looking usage still never reaches the guaranteed tier', () {
      // Even with usageConfidence forced to verified in the context (simulating
      // a hypothetical future signal), bogo ALWAYS carries a cycleRedemptionLimit
      // in real data, so it needs verified usage AND explicit platform — this
      // test proves the GATE logic, not that verified is unreachable (Task 11
      // proves verified is unreachable from real repository data).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'Zomato'),
        rules: [_bogoRule(partners: {'Zomato'})],
        contexts: {
          'c1': const MovieDealContext(isOwned: true, usageConfidence: MovieDealUsageConfidence.unverified),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
      expect(result.bestPotentialOwned!.cardId, 'c1');
    });

    test('a percentDiscount candidate with verified usage and explicit platform reaches the guaranteed tier', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_percentRule(percent: 10, partners: {'BookMyShow'})],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNotNull);
      expect(result.bestGuaranteedOwned!.cardId, 'c2');
    });

    test('a milestone candidate never reaches the guaranteed tier, regardless of milestoneSpend', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'BookMyShow'})],
        contexts: {
          'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
    });

    test('a fixedDiscount candidate with a cycleAmountCap never reaches the guaranteed tier', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_fixedDiscountWithCapRule()],
        contexts: {'c4': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
    });
  });

  group('platform confidence uses eligibleMoviePlatforms, never raw partners', () {
    test('searching "Uber" against the multi-partner milestone rule does NOT yield explicit confidence', () {
      // partners: {Uber, cult.fit Live, BookMyShow, TataCliQ} but
      // eligibleMoviePlatforms only ever resolves to {BookMyShow} (design
      // spec §5/§8 regression requirement).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'Uber'),
        rules: [_milestoneRule(partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'})],
        contexts: {'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c3');
      expect(candidate.platformConfidence, isNot(MovieDealPlatformConfidence.explicit));
    });

    test('searching "BookMyShow" against the same rule DOES yield explicit confidence', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'})],
        contexts: {'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c3');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.explicit);
    });
  });

  group('notRequested confidence and its precedence with communityConfirmed', () {
    test('empty eligibleMoviePlatforms, no platform requested, no confirmations => notRequested', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [_percentRule()], // no partners
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.notRequested);
    });

    test('empty eligibleMoviePlatforms, no platform requested, but a confirmation exists => communityConfirmed, never notRequested', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [_percentRule()],
        contexts: {
          'c2': const MovieDealContext(isOwned: true, confirmedPlatforms: {'PVR'}),
        },
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.communityConfirmed);
    });

    test('empty eligibleMoviePlatforms, a SPECIFIC platform requested, no confirmations => unconfirmed, never notRequested', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'PVR'),
        rules: [_percentRule()],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.unconfirmed);
    });
  });

  group('independent owned/overall ranking within each tier', () {
    test('keeps guaranteed owned and overall winners independent — no ownership bonus', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [
          _percentRule(cardId: 'owned-card', percent: 5, partners: {'BookMyShow'}),
          _percentRule(cardId: 'unowned-card', percent: 20, partners: {'BookMyShow'}),
        ],
        contexts: {
          'owned-card': const MovieDealContext(isOwned: true),
          'unowned-card': const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned!.cardId, 'owned-card');
      expect(result.bestGuaranteedOverall!.cardId, 'unowned-card');
      expect(result.bestGuaranteedOverall!.savings, greaterThan(result.bestGuaranteedOwned!.savings));
    });

    test('shared winner appears as the same candidate in both guaranteed fields', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_percentRule(cardId: 'c1', percent: 10, partners: {'BookMyShow'})],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned!.cardId, result.bestGuaranteedOverall!.cardId);
      expect(result.bestGuaranteedOwned!.benefitId, result.bestGuaranteedOverall!.benefitId);
    });
  });

  group('rewardMultiplier never gets a computed rupee savings figure', () {
    test('rewardMultiplier candidate has zero computed savings', () {
      final multiplierRule = MovieDealRule(
        benefitId: 'b-mult',
        catalogCardId: 'c5',
        title: '10X points',
        offerType: MovieDealOfferType.rewardMultiplier,
        rewardMultiplierRate: 10,
        rewardMultiplierUnit: 'points per Rs.150',
        qualifyingCategories: const {'movies'},
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [multiplierRule],
        contexts: {'c5': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c5');
      expect(candidate.savings, 0);
    });
  });

  group('never invents commercial terms', () {
    test('savings are always clamped to eligible spend, never negative', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 100),
        rules: [_bogoRule()], // cap of 500 far exceeds a 100-rupee ticket
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, lessThanOrEqualTo(100));
      expect(candidate.savings, greaterThanOrEqualTo(0));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_evaluator_test.dart`
Expected: FAIL — compile error, `movie_deal_evaluator.dart` and `evaluateMovieDeals` don't exist yet.

- [ ] **Step 3: Write the evaluator**

```dart
// lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart
import 'movie_deal_candidate.dart';
import 'movie_deal_rule.dart';
import 'movie_platform_aliases.dart';
import 'movie_ticket_request.dart';

export 'movie_deal_candidate.dart';

/// Evaluates every rule against one request, returning candidates split into
/// guaranteed and potential tiers, each independently ranked into owned/
/// overall (design spec §5). Ownership is never a scoring bonus.
MovieDealsRecommendation evaluateMovieDeals({
  required MovieTicketRequest request,
  required List<MovieDealRule> rules,
  required Map<String, MovieDealContext> contexts,
  required DateTime now,
}) {
  final candidates = <MovieDealCandidate>[];
  final rejected = <RejectedMovieDealCandidate>[];

  for (final rule in rules) {
    final context = contexts[rule.catalogCardId] ?? const MovieDealContext();
    final reason = _ineligibilityReason(rule, request, context, now);
    if (reason != null) {
      rejected.add(RejectedMovieDealCandidate(
        cardId: rule.catalogCardId,
        benefitId: rule.benefitId,
        rule: rule,
        reason: reason,
      ));
      continue;
    }

    final platformConfidence = _platformConfidence(rule, request, context);
    final gross = request.totalAmount;
    final saving = _calculateSavings(rule, request, gross);
    candidates.add(MovieDealCandidate(
      cardId: rule.catalogCardId,
      benefitId: rule.benefitId,
      title: rule.title,
      rule: rule,
      isOwned: context.isOwned,
      grossAmount: gross,
      savings: saving,
      finalAmount: gross - saving,
      usageConfidence: context.usageConfidence,
      platformConfidence: platformConfidence,
      explanation: _explanation(rule, saving, context.usageConfidence),
    ));
  }

  final guaranteed = candidates.where(_isGuaranteed).toList()..sort(_compareCandidates);
  final potential = candidates.where((c) => !_isGuaranteed(c)).toList()..sort(_compareCandidates);

  final guaranteedOwned = guaranteed.where((c) => c.isOwned).toList();
  final potentialOwned = potential.where((c) => c.isOwned).toList();

  return MovieDealsRecommendation(
    candidates: candidates,
    rejectedCandidates: rejected,
    bestGuaranteedOwned: guaranteedOwned.isEmpty ? null : guaranteedOwned.first,
    bestGuaranteedOverall: guaranteed.isEmpty ? null : guaranteed.first,
    bestPotentialOwned: potentialOwned.isEmpty ? null : potentialOwned.first,
    bestPotentialOverall: potential.isEmpty ? null : potential.first,
  );
}

/// Design spec §5's corrected gate: usage certainty AND platform certainty,
/// both required. Note this can never be true for bogo (real rows always
/// carry a cycleRedemptionLimit, and no real signal exists to make usage
/// verified for a capped type — see Task 11's repository), fixedDiscount
/// with a cycleAmountCap, or milestone (no benefit_id column exists in
/// statement_milestone_cache to verify against) — this is a genuine
/// consequence of real data-availability limits, not special-cased here.
bool _isGuaranteed(MovieDealCandidate candidate) {
  final hasNoCapToVerify = (candidate.rule.offerType == MovieDealOfferType.percentDiscount) ||
      (candidate.rule.offerType == MovieDealOfferType.bogo &&
          candidate.rule.cycleRedemptionLimit == null);
  final usageOk = candidate.usageConfidence == MovieDealUsageConfidence.verified || hasNoCapToVerify;
  final platformOk = candidate.platformConfidence == MovieDealPlatformConfidence.explicit;
  return usageOk && platformOk;
}

String? _ineligibilityReason(
  MovieDealRule rule,
  MovieTicketRequest request,
  MovieDealContext context,
  DateTime now,
) {
  if (rule.validityStart != null && now.isBefore(rule.validityStart!)) {
    return 'Not active yet.';
  }
  if (rule.validityEnd != null && now.isAfter(rule.validityEnd!)) {
    return 'Rule has expired.';
  }
  if (!_platformMatches(rule, request)) return 'Platform is not eligible.';

  if (rule.offerType == MovieDealOfferType.milestone) {
    if (context.milestoneSpend == null) {
      return 'Milestone progress is unavailable.';
    }
    if (context.milestoneSpend! < rule.milestoneThreshold!) {
      return 'Milestone threshold was not met last month.';
    }
  }

  if (rule.offerType == MovieDealOfferType.bogo &&
      rule.cycleRedemptionLimit != null &&
      context.usageConfidence == MovieDealUsageConfidence.verified &&
      context.usedTransactions >= rule.cycleRedemptionLimit!) {
    return 'Monthly redemption limit has been reached.';
  }

  return null;
}

/// A rule with no recognized movie-platform data, or a search with no
/// preferred platform, always passes eligibility — platform CONFIDENCE (not
/// eligibility) is what distinguishes a confirmed match from an unconfirmed
/// one (design spec §5). Checks eligibleMoviePlatforms, never raw partners.
bool _platformMatches(MovieDealRule rule, MovieTicketRequest request) {
  final eligible = eligibleMoviePlatformsFor(rule);
  if (eligible.isEmpty) return true;
  if (request.preferredPlatform == null) return true;
  return eligible.any((p) => p.toLowerCase() == request.preferredPlatform!.toLowerCase());
}

MovieDealPlatformConfidence _platformConfidence(
  MovieDealRule rule,
  MovieTicketRequest request,
  MovieDealContext context,
) {
  final eligible = eligibleMoviePlatformsFor(rule);

  if (eligible.isNotEmpty) {
    if (request.preferredPlatform == null) return MovieDealPlatformConfidence.explicit;
    final matches = eligible.any((p) => p.toLowerCase() == request.preferredPlatform!.toLowerCase());
    if (matches) return MovieDealPlatformConfidence.explicit;
  }

  // eligibleMoviePlatforms is empty (or didn't match the specific search) —
  // check confirmations before falling to notRequested/unconfirmed.
  final hasAnyConfirmation = request.preferredPlatform == null
      ? context.confirmedPlatforms.isNotEmpty
      : context.confirmedPlatforms
          .any((p) => p.toLowerCase() == request.preferredPlatform!.toLowerCase());
  if (hasAnyConfirmation) return MovieDealPlatformConfidence.communityConfirmed;

  return request.preferredPlatform == null
      ? MovieDealPlatformConfidence.notRequested
      : MovieDealPlatformConfidence.unconfirmed;
}

double _calculateSavings(
    MovieDealRule rule, MovieTicketRequest request, double gross) {
  final tickets = request.numberOfTickets;
  final price = request.pricePerTicket;
  double savings;
  switch (rule.offerType) {
    case MovieDealOfferType.bogo:
      final pairCount = tickets ~/ (rule.buyCount! + rule.freeCount!);
      final perPairDiscount = rule.perTransactionCap != null
          ? (price < rule.perTransactionCap! ? price : rule.perTransactionCap!)
          : price;
      savings = pairCount * rule.freeCount! * perPairDiscount;
    case MovieDealOfferType.percentDiscount:
      savings = gross * ((rule.discountPercent ?? 0) / 100);
    case MovieDealOfferType.fixedDiscount:
      savings = rule.fixedAmount ?? 0;
    case MovieDealOfferType.annualAllowance:
      savings = rule.annualCap ?? 0;
    case MovieDealOfferType.milestone:
      savings = rule.milestoneReward ?? 0;
    case MovieDealOfferType.rewardMultiplier:
      // Never converted to a rupee figure — design spec §7 step 6.
      savings = 0;
  }
  if (rule.offerType == MovieDealOfferType.fixedDiscount &&
      rule.cycleAmountCap != null &&
      savings > rule.cycleAmountCap!) {
    savings = rule.cycleAmountCap!;
  }
  return savings.clamp(0, gross).toDouble();
}

String _explanation(MovieDealRule rule, double savings,
        MovieDealUsageConfidence confidence) =>
    switch (rule.offerType) {
      MovieDealOfferType.rewardMultiplier =>
        '${rule.rewardMultiplierRate} ${rule.rewardMultiplierUnit} (points program, not a direct discount).',
      MovieDealOfferType.bogo =>
        'BOGO — up to ₹${rule.perTransactionCap?.toStringAsFixed(0)} off, '
            '${rule.cycleRedemptionLimit} redemptions/month.',
      _ => '${rule.offerType.name} saves ₹${savings.toStringAsFixed(2)} (${confidence.name} usage).',
    };

int _compareCandidates(MovieDealCandidate left, MovieDealCandidate right) {
  var result = right.savings.compareTo(left.savings);
  if (result != 0) return result;
  result = left.finalAmount.compareTo(right.finalAmount);
  if (result != 0) return result;
  result = _platformConfidenceRank(right.platformConfidence)
      .compareTo(_platformConfidenceRank(left.platformConfidence));
  if (result != 0) return result;
  result = right.rule.displayPriority.compareTo(left.rule.displayPriority);
  if (result != 0) return result;
  result = left.cardId.compareTo(right.cardId);
  return result != 0 ? result : left.benefitId.compareTo(right.benefitId);
}

/// Design spec §5: communityConfirmed > unconfirmed > notRequested — a rule
/// someone actively tried and failed to confirm (or partially confirmed)
/// carries more information than one whose platform was never asked about.
/// Only meaningful within the potential tier — every guaranteed-tier member
/// already has explicit confidence by definition.
int _platformConfidenceRank(MovieDealPlatformConfidence confidence) =>
    switch (confidence) {
      MovieDealPlatformConfidence.explicit => 3,
      MovieDealPlatformConfidence.communityConfirmed => 2,
      MovieDealPlatformConfidence.unconfirmed => 1,
      MovieDealPlatformConfidence.notRequested => 0,
    };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_evaluator_test.dart`
Expected: PASS (16 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
git commit -m "feat: evaluate movie deals with guaranteed/potential tiers and eligibleMoviePlatforms confidence"
```

---

## Task 8: Migrations — resolve both §3.1 P0s, then add the confirmation table

**Files:**
- Create: `supabase/migrations/20260711043700_fix_benefit_column_types.sql` (P0 #2 — column-type ordering fix)
- Create: `supabase/migrations/20260802100000_curated_movie_benefit_mappings.sql` (P0 #1 + #3 — curated mappings, never a mechanical restore)
- Create: `supabase/migrations/20260802100100_benefit_platform_confirmations.sql` (§6 — new additive table)

**Design spec §3.1 constraint — ordering matters.** `20260711043541_initial_schema.sql` creates `benefits.partners`/`exclusions`/`regions` as `TEXT[]`; `20260711043900_restore_reference_data.sql` (359 seconds later) seeds them with JSON-array literal syntax, which `COPY` cannot load into a genuine `TEXT[]` column. The corrective migration MUST be timestamped between these two — `20260711043700` — not appended after the existing chain, or the seed load fails before the chain ever reaches a later fix.

- [ ] **Step 1: Write the column-type fix migration**

```sql
-- supabase/migrations/20260711043700_fix_benefit_column_types.sql
--
-- Design spec §3.1 P0 #2. Timestamped BETWEEN 20260711043541_initial_schema.sql
-- (creates partners/exclusions/regions as TEXT[]) and
-- 20260711043900_restore_reference_data.sql (seeds them with JSON-array
-- literal syntax, which COPY cannot load into TEXT[]). This ordering is
-- load-bearing — a fix appended after the existing chain would run too late
-- to matter, since the seed load would already have failed.
BEGIN;

ALTER TABLE benefits
  ALTER COLUMN partners TYPE JSONB USING
    CASE
      WHEN partners IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(partners)
    END,
  ALTER COLUMN partners SET DEFAULT '[]'::jsonb;

ALTER TABLE benefits
  ALTER COLUMN exclusions TYPE JSONB USING
    CASE
      WHEN exclusions IS NULL THEN '{}'::jsonb
      ELSE to_jsonb(exclusions)
    END,
  ALTER COLUMN exclusions SET DEFAULT '{}'::jsonb;

ALTER TABLE benefits
  ALTER COLUMN regions TYPE JSONB USING
    CASE
      WHEN regions IS NULL THEN '[]'::jsonb
      ELSE to_jsonb(regions)
    END,
  ALTER COLUMN regions SET DEFAULT '[]'::jsonb;

COMMENT ON COLUMN benefits.partners IS
  'Partner names where benefit is applicable (JSONB — matches production data shape, corrected from TEXT[] before seed data loads).';
COMMENT ON COLUMN benefits.exclusions IS
  'Exclusion conditions, e.g. {"mcc_codes": [...], "merchants": [...], "categories": [...]} (JSONB — corrected from TEXT[] before seed data loads).';
COMMENT ON COLUMN benefits.regions IS
  'Geographic regions where benefit is valid (JSONB — corrected from TEXT[] before seed data loads).';

COMMIT;
```

- [ ] **Step 2: Verify the filename timestamp is correct**

Run: `echo "20260711043700_fix_benefit_column_types.sql" | sort -c <(printf '20260711043541_initial_schema.sql\n20260711043700_fix_benefit_column_types.sql\n20260711043900_restore_reference_data.sql\n')`
Expected: no output (silent success means the three filenames already sort in the correct chronological order — `43541 < 43700 < 43900`). If this errors, the filename timestamp is wrong; fix it before proceeding.

- [ ] **Step 3: Write the curated mappings migration**

Design spec §3.1 P0 #1 + #3 — this must NOT be a `SELECT` replaying the original deleted `card_benefit_mapping` rows. Cross-referencing every entertainment mapping against its benefit's own source URL found "SBI Card ELITE Free Movie Tickets" mapped to 15+ mostly-unrelated cards; only rows whose card name is internally consistent with the benefit's own source URL are inserted here. This is a starting curated set, not a claim of exhaustive commercial verification — real terms should still be reviewed against each issuer's published page before this feature is trusted in production, per §3.1's own caveat that internal consistency alone doesn't prove commercial accuracy.

```sql
-- supabase/migrations/20260802100000_curated_movie_benefit_mappings.sql
--
-- Design spec §3.1 P0 #1 + #3. card_benefit_mapping was emptied by
-- 20260713180753_normalize_card_benefit_mappings.sql and never repopulated.
-- This migration inserts ONLY mappings whose card name is internally
-- consistent with the benefit's own source_url — never a mechanical
-- restoration of the original (partly commercially-inaccurate) deleted set.
BEGIN;

-- "BookMyShow Discount" (fixedDiscount, monthly_cap 1500) → IDFC FIRST
-- Private, whose source_url is /credit-card/FIRSTPrivateCreditCard —
-- internally consistent.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE '%FIRST Private%'
  AND b.title = 'BookMyShow Discount'
  AND b.source_url ILIKE '%FIRSTPrivateCreditCard%'
ON CONFLICT DO NOTHING;

-- "Instant Discount on Bookmyshow" (percentDiscount, 10%) → Axis IndianOil,
-- whose source_url is /credit-card/indianoil-axis-bank-credit-card —
-- internally consistent.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE '%IndianOil%'
  AND b.title = 'Instant Discount on Bookmyshow'
  AND b.source_url ILIKE '%indianoil-axis-bank%'
ON CONFLICT DO NOTHING;

-- "Twin ticket treats" (bogo, Zomato) → IDFC FIRST Mayura, whose source_url
-- is /credit-card/metal-credit-card/mayura — internally consistent.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE '%Mayura%'
  AND b.title = 'Twin ticket treats'
  AND b.source_url ILIKE '%mayura%'
ON CONFLICT DO NOTHING;

-- "Buy-1-Get-1 Movie Ticket Offer" (bogo, no recorded partner) → IDFC FIRST
-- Wealth, whose source_url is /credit-card/wealth — internally consistent.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE '%Wealth%'
  AND b.title = 'Buy-1-Get-1 Movie Ticket Offer'
  AND b.source_url ILIKE '%wealth%'
ON CONFLICT DO NOTHING;

-- "25% off on movie tickets" → IDFC FIRST Millennia, whose source_url is
-- /credit-card/millennia — internally consistent.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE '%Millennia%'
  AND b.title = '25% off on movie tickets'
  AND b.source_url ILIKE '%millennia%'
ON CONFLICT DO NOTHING;

-- "Monthly Vouchers on Spends" / "Monthly Milestone Benefits" (milestone,
-- Uber/cult.fit/BookMyShow/TataCliQ) → HDFC Diners Club Black, whose
-- source_url is /credit-cards/diners-club-black — internally consistent.
INSERT INTO card_benefit_mapping (card_id, benefit_id, display_priority)
SELECT c.id, b.benefit_id, 1
FROM card_catalog c, benefits b
WHERE c.card_name ILIKE '%Diners Club Black%'
  AND b.title IN ('Monthly Vouchers on Spends', 'Monthly Milestone Benefits')
  AND b.source_url ILIKE '%diners-club-black%'
ON CONFLICT DO NOTHING;

COMMIT;
```

- [ ] **Step 4: Write the confirmation table migration**

Design spec §6 — every integrity/security correction included from the start.

```sql
-- supabase/migrations/20260802100100_benefit_platform_confirmations.sql
--
-- Design spec §6. Additive only — does not alter benefits, card_benefit_mapping,
-- user_cards, or transactions.
BEGIN;

CREATE TABLE benefit_platform_confirmations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  benefit_id    uuid NOT NULL REFERENCES benefits(benefit_id),
  platform      text NOT NULL CHECK (trim(platform) <> ''),
  platform_key  text GENERATED ALWAYS AS (lower(trim(platform))) STORED,
  user_id       uuid NOT NULL REFERENCES auth.users(id),
  confirmed_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, benefit_id, platform_key)
);

CREATE INDEX idx_benefit_platform_confirmations_lookup
  ON benefit_platform_confirmations(benefit_id, platform_key);

ALTER TABLE benefit_platform_confirmations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated insert own confirmation"
  ON benefit_platform_confirmations FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE VIEW benefit_platform_confirmation_counts
  WITH (security_invoker = false) AS
  SELECT benefit_id, platform_key, count(DISTINCT user_id) AS confirmation_count
  FROM benefit_platform_confirmations
  GROUP BY benefit_id, platform_key;

REVOKE ALL ON benefit_platform_confirmations FROM authenticated;
GRANT INSERT ON benefit_platform_confirmations TO authenticated;
GRANT SELECT ON benefit_platform_confirmation_counts TO authenticated;

COMMIT;
```

- [ ] **Step 5: Apply all three migrations to a clean local database**

Run: `supabase db reset`
Expected: exits 0. This proves the corrected column-type migration lands in the right order and the seed data loads successfully against it — the actual regression guard §3.1 requires, not an inference from reading the files.

- [ ] **Step 6: Verify the mapping migration produced at least one row**

Run: `supabase db psql -c "select count(*) from card_benefit_mapping where benefit_id in (select benefit_id from benefits where benefit_category = 'entertainment' or title ilike '%movie%' or title ilike '%bookmyshow%')"`
Expected: a count >= 1. If 0, one of the curated `INSERT` statements didn't match any real `card_catalog`/`benefits` row — check the actual card names/source URLs in the live database and correct the `ILIKE` patterns above (they were written from the migration file's static text, not verified against a running database).

- [ ] **Step 7: Verify the confirmation table's permission model**

Run: `supabase db psql -c "set role authenticated; select * from benefit_platform_confirmations;"`
Expected: a permission-denied error (proves the `REVOKE` took effect).

Run: `supabase db psql -c "set role authenticated; select * from benefit_platform_confirmation_counts;"`
Expected: succeeds, returns zero rows (empty table, but no permission error — proves the aggregate view is readable).

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260711043700_fix_benefit_column_types.sql supabase/migrations/20260802100000_curated_movie_benefit_mappings.sql supabase/migrations/20260802100100_benefit_platform_confirmations.sql
git commit -m "feat: fix benefit column types, curate movie benefit mappings, add confirmation table"
```

---

## Task 9: Automated permissions test for `benefit_platform_confirmations`

**Files:**
- Create: `test/supabase/benefit_platform_confirmations_permissions_test.dart`

Design spec §12 requires this as an automated test, not only the manual `supabase db psql` checks in Task 8's steps 6–7 — a manual check doesn't survive as a regression guard once this feature ships. This test requires a live local Supabase instance (`supabase start`), since RLS/grant behavior cannot be faked the way the repository's unit tests can — it is an integration test, run separately from the pure-Dart unit suite.

- [ ] **Step 1: Write the test**

```dart
// test/supabase/benefit_platform_confirmations_permissions_test.dart
//
// Integration test against a LIVE local Supabase instance. Run `supabase
// start` first. This proves the exact SQL grants from Task 8 behave as
// claimed — a fake data source cannot catch a REVOKE/GRANT mistake that
// only manifests against real Postgres role permissions (design spec §12).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late String testUserId;
  const testBenefitId = '75c8316b-3fcf-40de-af2c-18838942d5b5'; // real seed row

  setUpAll(() async {
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
    client = Supabase.instance.client;
    final auth = await client.auth.signUp(
      email: 'movie-deals-permissions-test@example.com',
      password: 'test-password-1234',
    );
    testUserId = auth.user!.id;
  });

  test('authenticated role cannot SELECT the base confirmations table directly', () async {
    expect(
      () => client.from('benefit_platform_confirmations').select(),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('authenticated role CAN SELECT the aggregate confirmation_counts view', () async {
    final result = await client.from('benefit_platform_confirmation_counts').select();
    expect(result, isA<List>()); // succeeds, even if empty — no permission error
  });

  test('a duplicate confirmation insert via upsert/ON CONFLICT succeeds silently, never raises 23505', () async {
    await client.from('benefit_platform_confirmations').upsert(
      {'benefit_id': testBenefitId, 'platform': 'BookMyShow', 'user_id': testUserId},
      onConflict: 'user_id,benefit_id,platform_key',
      ignoreDuplicates: true,
    );

    // The second identical insert must not throw — this is the exact
    // mechanism Task 11's insertConfirmation() uses.
    await expectLater(
      client.from('benefit_platform_confirmations').upsert(
        {'benefit_id': testBenefitId, 'platform': 'BookMyShow', 'user_id': testUserId},
        onConflict: 'user_id,benefit_id,platform_key',
        ignoreDuplicates: true,
      ),
      completes,
    );

    final counts = await client
        .from('benefit_platform_confirmation_counts')
        .select()
        .eq('benefit_id', testBenefitId)
        .eq('platform_key', 'bookmyshow');
    expect((counts as List).first['confirmation_count'], 1); // not 2 — dedup confirmed
  });
}
```

- [ ] **Step 2: Start the local Supabase instance**

Run: `supabase start`
Expected: local Postgres/PostgREST/Auth services come up; note the printed `anon key` for the next step.

- [ ] **Step 3: Run the test**

Run: `flutter test test/supabase/benefit_platform_confirmations_permissions_test.dart --dart-define=SUPABASE_ANON_KEY=<the anon key printed by supabase start>`
Expected: PASS (3 tests). If test 1 fails (SELECT succeeds when it shouldn't), the `REVOKE ALL ... FROM authenticated` in Task 8's migration didn't take effect — re-check the migration ran and re-verify with `supabase db psql`. If test 3 fails with a `23505` error, the `onConflict`/`ignoreDuplicates` parameters aren't reaching Postgres as a true `ON CONFLICT DO NOTHING` — check the Supabase client library version supports this upsert shape.

- [ ] **Step 4: Commit**

```bash
git add test/supabase/benefit_platform_confirmations_permissions_test.dart
git commit -m "test: add automated permissions integration test for benefit_platform_confirmations"
```

---

## Task 10: Repository, part 1 — widened single-`.or()` fetch and source construction

**Files:**
- Create: `lib/core/repositories/movie_deals_repository.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_repository_test.dart`

Tested against a fake `MovieDealsDataSource` — no network/credentials needed to run this test file.

- [ ] **Step 1: Write the failing tests**

```dart
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
          .loadSnapshot('user1', const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300))
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
          .loadSnapshot('user1', const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300))
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
          .loadSnapshot('user1', const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300))
          .then((snapshot) {
        final source = snapshot.sources.first;
        expect(source.validityStart, DateTime(2026, 1, 1));
        expect(source.validityEnd, DateTime(2026, 12, 31));
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: FAIL — compile error, `movie_deals_repository.dart` does not exist yet.

- [ ] **Step 3: Write the repository (part 1 — interfaces, source construction)**

```dart
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
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  );

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
    MovieTicketRequest request,
  ) async {
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

    final benefitById = {
      for (final benefit in benefits) _idForBenefit(benefit): benefit,
    };
    final cardById = {for (final card in cards) _string(card['id']): card};

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
    // Part 2 (Task 11) fills in `contexts`; this task returns them empty so
    // the file compiles and the source-construction tests above can pass
    // independently of context-building logic.
    return MovieDealsSnapshot(sources: sources, contexts: const {});
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit is deferred to Task 11**

The `loadSnapshot` method above returns empty `contexts` and has no live Supabase data-source implementation yet — Task 11 completes both. Proceed directly; both tasks' files commit together there.

**Post-implementation correction:** code-quality review of the committed Tasks 10+11 code found that `loadSnapshot`'s internal `final now = DateTime.now();` (used for milestone cycle-completion gating) made a milestone-cycle-selection test's correctness depend on the real wall-clock date at whatever moment the suite happened to run — the test passed only by coincidence and would have started failing once real time passed its later fixture date (2026-08-31). The COMMITTED code and test file now both accept `now` as an explicit required parameter on `loadSnapshot` (`request` becomes a named-parameter boundary: `loadSnapshot(userId, request, {required DateTime now})`), matching `evaluateMovieDeals`'s (Task 7) established pattern — every `.loadSnapshot(...)` call site above in this task's own spec text is missing this parameter and reflects the pre-fix code; the actual committed file and test differ from what's shown above in exactly this one respect. Task 12's provider-wiring code (further below in this document) has already been corrected to pass `now:` to both `loadSnapshot` and `evaluateMovieDeals` from a single computed value.

---

## Task 11: Repository, part 2 — context-building, milestone cycle-precision, live data source

**Files:**
- Modify: `lib/core/repositories/movie_deals_repository.dart` (complete `loadSnapshot`, add `SupabaseMovieDealsDataSource`)
- Modify: `test/features/benefits/movie_deals/movie_deals_repository_test.dart` (append tests)

- [ ] **Step 1: Add the failing tests**

Append to `test/features/benefits/movie_deals/movie_deals_repository_test.dart`, inside `main()` (after the existing group), and update `_FakeDataSource`/`_benefitRow` calls in existing tests only if needed (they should already compile against the interface from Task 10):

```dart
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
          {'benefit_id': 'b1', 'platform': 'PVR'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      return repository
          .loadSnapshot('user1', const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300))
          .then((snapshot) {
        expect(snapshot.contexts[('catalog-card-1', 'b1')]?.confirmedPlatforms, contains('PVR'));
        expect(snapshot.contexts[('catalog-card-1', 'b2')]?.confirmedPlatforms ?? const {}, isNot(contains('PVR')));
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
      );
      expect(snapshot.contexts[('catalog-card-1', 'b1')]?.usageConfidence, MovieDealUsageConfidence.unverified);
    });

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
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: FAIL — the new tests expect populated `contexts`, but `loadSnapshot` from Task 10 always returns `contexts: const {}`.

- [ ] **Step 3: Complete `loadSnapshot` and add the live data source**

Replace the `loadSnapshot` method body in `lib/core/repositories/movie_deals_repository.dart` (the `return MovieDealsSnapshot(sources: sources, contexts: const {});` line and everything needed to build real contexts):

```dart
  @override
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  ) async {
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
    // still-accumulating current cycle.
    final now = DateTime.now();
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
```

Also add these free functions after the `_exclusionCategories` helper (still in the same file):

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: PASS (8 tests total)

- [ ] **Step 5: Commit both Task 10 and Task 11 files together**

```bash
git add lib/core/repositories/movie_deals_repository.dart test/features/benefits/movie_deals/movie_deals_repository_test.dart
git commit -m "feat: complete movie deals repository — widened .or() fetch, per-benefit confirmations, milestone cycle precision"
```

---

## Task 12: Wire the repository provider and search `FutureProvider`

**Files:**
- Modify: `lib/core/providers/repository_providers.dart`
- Create: `lib/features/benefits/movie_deals/providers/movie_deals_provider.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_provider_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/benefits/movie_deals/movie_deals_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';
import 'package:cardcompass/features/benefits/movie_deals/providers/movie_deals_provider.dart';

void main() {
  test('movieDealsSearchProvider exposes an unavailable status when not authenticated', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const request = MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300);
    final result = await container.read(movieDealsSearchProvider(request).future);

    expect(result.status, MovieDealsStatus.unavailable);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_provider_test.dart`
Expected: FAIL — compile error, `movie_deals_provider.dart` and `movieDealsSearchProvider` don't exist yet.

- [ ] **Step 3: Add `movieDealsRepositoryProvider`**

Read `lib/core/providers/repository_providers.dart` first, then add a fourth provider following the exact same shape as the existing three:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/cards_repository.dart';
import '../repositories/transactions_repository.dart';
import '../repositories/statements_repository.dart';
import '../repositories/movie_deals_repository.dart';
import 'supabase_provider.dart';

final cardsRepositoryProvider = Provider<CardsRepository>((ref) {
  return CardsRepository(ref.watch(supabaseClientProvider));
});

final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) {
  return TransactionsRepository(ref.watch(supabaseClientProvider));
});

final statementsRepositoryProvider = Provider<StatementsRepository>((ref) {
  return StatementsRepository(ref.watch(supabaseClientProvider));
});

final movieDealsRepositoryProvider = Provider<MovieDealsRepository>((ref) {
  return MovieDealsSupabaseRepository(
    SupabaseMovieDealsDataSource(ref.watch(supabaseClientProvider)),
  );
});
```

- [ ] **Step 4: Write `movie_deals_provider.dart`**

```dart
// lib/features/benefits/movie_deals/providers/movie_deals_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_deal_evaluator.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_deal_rule_normalizer.dart';
import '../domain/movie_ticket_request.dart';

/// Runs one Movie Deals search: loads a snapshot keyed by
/// (catalogCardId, benefitId), normalizes every source, evaluates accepted
/// rules, and returns a guaranteed/potential-tiered recommendation.
/// Returns MovieDealsStatus.unavailable rather than an empty no-deal
/// result on any failure (design spec §11).
final movieDealsSearchProvider =
    FutureProvider.family<MovieDealsRecommendation, MovieTicketRequest>(
        (ref, request) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );
  }

  try {
    // Computed once and reused for both calls below — movie_deals_repository.dart's
    // loadSnapshot() and evaluateMovieDeals() both gate time-sensitive logic
    // (milestone cycle-completion, rule validity dates) on `now`; calling
    // DateTime.now() separately at each call site risks the two moments
    // straddling a boundary (e.g. midnight) and disagreeing about which
    // cycle is "current" within the same single search.
    final now = DateTime.now();
    final repository = ref.read(movieDealsRepositoryProvider);
    final snapshot = await repository.loadSnapshot(user.id, request, now: now);

    final rules = <MovieDealRule>[];
    for (final source in snapshot.sources) {
      final normalized = normalizeMovieDealRule(source);
      if (normalized case AcceptedMovieDealRule(:final rule)) {
        rules.add(rule);
      }
    }

    // The evaluator's contexts map is keyed by catalogCardId only (matching
    // its rule.catalogCardId lookup); the repository snapshot is keyed by
    // (catalogCardId, benefitId) for per-benefit confirmation scoping.
    // Re-key per rule at evaluation time so each rule gets its OWN
    // benefit's context, not a card-wide union.
    final contextsByCard = <String, MovieDealContext>{};
    for (final rule in rules) {
      final context = snapshot.contexts[(rule.catalogCardId, rule.benefitId)];
      if (context != null) contextsByCard[rule.catalogCardId] = context;
    }

    return evaluateMovieDeals(
      request: request,
      rules: rules,
      contexts: {
        for (final rule in rules)
          if (snapshot.contexts[(rule.catalogCardId, rule.benefitId)] != null)
            rule.catalogCardId: snapshot.contexts[(rule.catalogCardId, rule.benefitId)]!,
      },
      now: now,
    );
  } catch (_) {
    return const MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );
  }
});
```

**Note on the re-keying above:** this works correctly only because the evaluator (Task 7) looks up `contexts[rule.catalogCardId]` per rule during a single pass over `rules` — if two rules on this plan's `rules` list ever shared the same `catalogCardId` with DIFFERENT `benefitId`s, the map-literal construction above (`{for (final rule in rules) ...: ...}`) would have the LAST rule's context win for that card key, silently discarding the other. This is a real limitation worth flagging rather than silently accepting: if a card has two movie benefits, this construction can leak one benefit's confirmedPlatforms onto the other's evaluation — the exact same-card leak the design spec's §5 correction was written to prevent, just reintroduced here at the provider layer instead of the repository layer. Task 7's evaluator signature (`Map<String, MovieDealContext> contexts`, single card-keyed map) does not actually support per-rule distinct contexts for same-card rules. **This must be fixed before Task 12 is considered done — do not proceed to Task 13 with this known regression.** Revise `evaluateMovieDeals`'s signature (Task 7, already committed) to accept `Map<(String, String), MovieDealContext> contexts` keyed by `(catalogCardId, benefitId)`, matching the repository's snapshot shape exactly, and update its lookup at the top of the evaluation loop from `contexts[rule.catalogCardId]` to `contexts[(rule.catalogCardId, rule.benefitId)]`. Re-run Task 7's full test suite after this change to confirm no regression, then write this provider directly against the corrected signature — passing `snapshot.contexts` straight through with no re-keying step at all:

```dart
    return evaluateMovieDeals(
      request: request,
      rules: rules,
      contexts: snapshot.contexts,
      now: now,
    );
```

This removes the flawed re-keying block above entirely — the corrected evaluator signature accepts the repository's native `(catalogCardId, benefitId)`-keyed map directly, with no lossy intermediate step. `now` here is the same value already computed once at the top of the provider body (see the `loadSnapshot(..., now: now)` call above) — not a fresh `DateTime.now()` call, for the same straddling-a-boundary reason noted there.

- [ ] **Step 5: Go back and fix Task 7's evaluator signature**

Before running this task's tests, apply the fix described in Step 4's note: in `lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart`, change `evaluateMovieDeals`'s `contexts` parameter type from `Map<String, MovieDealContext>` to `Map<(String, String), MovieDealContext>`, and change the lookup line inside the evaluation loop from:
```dart
    final context = contexts[rule.catalogCardId] ?? const MovieDealContext();
```
to:
```dart
    final context = contexts[(rule.catalogCardId, rule.benefitId)] ?? const MovieDealContext();
```
Then update every test in `test/features/benefits/movie_deals/movie_deal_evaluator_test.dart` (Task 7) that constructs a `contexts:` map with plain string keys (e.g. `{'c1': const MovieDealContext(...)}`) to use the tuple key matching that test's rule's `benefitId` (e.g. `{('c1', 'b-bogo'): const MovieDealContext(...)}` — check each test's `_bogoRule`/`_percentRule`/`_milestoneRule`/`_fixedDiscountWithCapRule` helper for its exact `benefitId` value before updating).

Run: `flutter test test/features/benefits/movie_deals/movie_deal_evaluator_test.dart`
Expected: PASS (16 tests, unchanged count) — confirms the signature change didn't break existing evaluator behavior, only its key type.

- [ ] **Step 6: Run this task's test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_provider_test.dart`
Expected: PASS (1 test)

- [ ] **Step 7: Commit**

```bash
git add lib/core/providers/repository_providers.dart lib/features/benefits/movie_deals/providers/movie_deals_provider.dart lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart test/features/benefits/movie_deals/movie_deals_provider_test.dart test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
git commit -m "feat: wire movie deals provider; key evaluator contexts by (catalogCardId, benefitId)"
```

---

## Task 13: Movie Deals screen — input form

**Files:**
- Create: `lib/features/benefits/movie_deals/screens/movie_deals_screen.dart`

Ports the main repo's `MovieAnalyzerTab` form layout (header, ticket/price fields, quick-select chips, platform/cinema dropdowns, live total, action button) using THIS worktree's real theme tokens (`AppColors.neonCyan`, Space Grotesk/Inter — design spec §8's correction, never `AppTheme.primaryColor`/"Plus Jakarta Sans"). The platform dropdown is sourced from `moviePlatformAliases`' canonical display values, not a hardcoded list — design spec §8's correction ensures "Zomato" (the real partner for "Twin ticket treats") is selectable.

- [ ] **Step 1: Write the screen**

```dart
// lib/features/benefits/movie_deals/screens/movie_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_platform_aliases.dart';
import '../domain/movie_ticket_request.dart';
import 'movie_deals_results.dart';

class MovieDealsScreen extends ConsumerStatefulWidget {
  const MovieDealsScreen({super.key});

  @override
  ConsumerState<MovieDealsScreen> createState() => _MovieDealsScreenState();
}

class _MovieDealsScreenState extends ConsumerState<MovieDealsScreen> {
  final _ticketCountController = TextEditingController();
  final _priceController = TextEditingController();
  String? _selectedPlatform;
  String? _selectedCinema;
  MovieTicketRequest? _submittedRequest;

  // Design spec §8 correction — sourced from the canonical registry
  // (movie_platform_aliases.dart), never a hardcoded guess at what
  // "sounds right" for movies. toSet().toList() dedupes "Zomato" (which
  // both "zomato" and "district" alias to) into one entry.
  static final _platforms = moviePlatformAliases.values.toSet().toList()..sort();
  static const _cinemas = ['PVR Cinemas', 'INOX', 'Cinepolis', 'Moviemax', 'SRS Cinemas', 'Wave Cinemas'];
  static const _ticketOptions = [2, 3, 4, 6];
  static const _priceOptions = [200, 250, 300, 400];

  @override
  void dispose() {
    _ticketCountController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _formValid {
    final tickets = int.tryParse(_ticketCountController.text);
    final price = double.tryParse(_priceController.text);
    return tickets != null && tickets > 0 && price != null && price > 0;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildInputForm(),
          const SizedBox(height: 24),
          _buildOptimizeButton(),
          const SizedBox(height: 24),
          if (_submittedRequest != null)
            MovieDealsResults(request: _submittedRequest!),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_movies_outlined, size: 24, color: AppColors.neonCyan),
            const SizedBox(width: 12),
            Text(
              'MOVIE TICKET OPTIMIZER',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Query ticket combinations across major platforms and calculate optimal savings route.',
          style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.25), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 14, color: AppColors.neonCyan),
              const SizedBox(width: 4),
              Text(
                'AI RULE OPTIMIZATION ENGINE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: AppColors.neonCyan,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputForm() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TICKET SPECIFICATIONS',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 11, letterSpacing: 1.0),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ticketCountController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(color: AppColors.textPrimary),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                    decoration: const InputDecoration(
                      labelText: 'Tickets',
                      prefixIcon: Icon(Icons.confirmation_number_outlined, color: AppColors.neonCyan),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(color: AppColors.textPrimary),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]')), LengthLimitingTextInputFormatter(5)],
                    decoration: const InputDecoration(
                      labelText: 'Price (₹)',
                      prefixIcon: Icon(Icons.currency_rupee, color: AppColors.neonCyan),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildQuickChips(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildPlatformDropdown()),
                const SizedBox(width: 16),
                Expanded(child: _buildCinemaDropdown()),
              ],
            ),
            const SizedBox(height: 20),
            _buildTotalAmount(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cinema filtering is not yet supported — no current benefit data is tied to a specific cinema chain.',
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedPlatform,
      isExpanded: true,
      dropdownColor: AppColors.surface1,
      decoration: const InputDecoration(
        labelText: 'Platform',
        prefixIcon: Icon(Icons.smartphone_outlined, color: AppColors.neonCyan),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('ANY PLATFORM', overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textSecondary)),
        ),
        ..._platforms.map((p) => DropdownMenuItem<String>(
              value: p,
              child: Text(p.toUpperCase(), overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textPrimary)),
            )),
      ],
      onChanged: (value) => setState(() => _selectedPlatform = value),
    );
  }

  Widget _buildCinemaDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCinema,
      isExpanded: true,
      dropdownColor: AppColors.surface1,
      decoration: const InputDecoration(
        labelText: 'Cinema',
        prefixIcon: Icon(Icons.theater_comedy_outlined, color: AppColors.neonCyan),
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('ANY CINEMA', overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textSecondary)),
        ),
        ..._cinemas.map((c) => DropdownMenuItem<String>(
              value: c,
              child: Text(c.toUpperCase(), overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.textPrimary)),
            )),
      ],
      onChanged: (value) => setState(() => _selectedCinema = value),
    );
  }

  Widget _buildQuickChips() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _ticketOptions.map((n) {
              final selected = int.tryParse(_ticketCountController.text) == n;
              return ChoiceChip(
                label: Text('$n TICKETS', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.bold, color: selected ? Colors.black : AppColors.textSecondary)),
                selectedColor: AppColors.neonCyan,
                backgroundColor: AppColors.surfaceVoid,
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _ticketCountController.text = '$n'),
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _priceOptions.map((p) {
              final selected = double.tryParse(_priceController.text) == p.toDouble();
              return ChoiceChip(
                label: Text('₹$p', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.bold, color: selected ? Colors.black : AppColors.textSecondary)),
                selectedColor: AppColors.neonCyan,
                backgroundColor: AppColors.surfaceVoid,
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() => _priceController.text = '$p'),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalAmount() {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVoid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('TOTAL BASE AMOUNT:', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 10, letterSpacing: 0.5)),
          Text(
            total > 0 ? '₹${total.toStringAsFixed(0)}' : '₹0',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.neonCyan, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizeButton() {
    final tickets = int.tryParse(_ticketCountController.text) ?? 0;
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final total = tickets * price;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _formValid
            ? () => setState(() {
                  _submittedRequest = MovieTicketRequest(
                    numberOfTickets: tickets,
                    pricePerTicket: price,
                    preferredPlatform: _selectedPlatform,
                    preferredCinema: _selectedCinema,
                  );
                })
            : null,
        icon: const Icon(Icons.bolt, color: Colors.black, size: 16),
        label: Text(
          total > 0 ? 'OPTIMIZE DEALS • ₹${total.toStringAsFixed(0)}' : 'OPTIMIZE DEALS',
          style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.black),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonCyan,
          disabledBackgroundColor: AppColors.surface3,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify it compiles standalone (except the deferred import)**

Run: `flutter analyze lib/features/benefits/movie_deals/screens/movie_deals_screen.dart`
Expected: One error — `movie_deals_results.dart` doesn't exist yet (Task 14). Expected at this point; do not stub it out.

- [ ] **Step 3: Commit is deferred to Task 14**

Proceed directly; both files commit together there.

---

## Task 14: Results panel — Guaranteed / Potential / reward-rate-only sections

**Files:**
- Create: `lib/features/benefits/movie_deals/screens/movie_deals_results.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_results_test.dart`

Design spec §8's corrected three-section layout: "Best Card You Own"/"Best Card Overall" from the `bestGuaranteed*` fields (falling back to `bestPotential*`, labeled as potential, when the guaranteed counterpart is null), a distinct muted "Potential" section for anything the guaranteed tier didn't surface, and `rewardMultiplier` candidates shown separately with their raw rate, never a computed savings figure.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/features/benefits/movie_deals/movie_deals_results_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';
import 'package:cardcompass/features/benefits/movie_deals/providers/movie_deals_provider.dart';
import 'package:cardcompass/features/benefits/movie_deals/screens/movie_deals_results.dart';

MovieDealCandidate _candidate({
  required String cardId,
  required bool isOwned,
  required double savings,
  MovieDealPlatformConfidence platformConfidence = MovieDealPlatformConfidence.explicit,
  MovieDealOfferType offerType = MovieDealOfferType.percentDiscount,
}) {
  final rule = MovieDealRule(
    benefitId: 'b-$cardId',
    catalogCardId: cardId,
    title: 'Test rule',
    offerType: offerType,
    discountPercent: 25,
    cardName: 'Card $cardId',
  );
  return MovieDealCandidate(
    cardId: cardId,
    benefitId: 'b-$cardId',
    title: 'Test rule',
    rule: rule,
    isOwned: isOwned,
    grossAmount: 1000,
    savings: savings,
    finalAmount: 1000 - savings,
    usageConfidence: MovieDealUsageConfidence.verified,
    platformConfidence: platformConfidence,
    explanation: 'saves ₹$savings',
  );
}

void main() {
  const request = MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300);

  testWidgets('renders distinct guaranteed owned and overall panels when winners differ', (tester) async {
    final owned = _candidate(cardId: 'owned', isOwned: true, savings: 100);
    final overall = _candidate(cardId: 'unowned', isOwned: false, savings: 300);
    final recommendation = MovieDealsRecommendation(
      candidates: [overall, owned],
      rejectedCandidates: const [],
      bestGuaranteedOwned: owned,
      bestGuaranteedOverall: overall,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('BEST CARD YOU OWN'), findsOneWidget);
    expect(find.text('BEST CARD OVERALL'), findsOneWidget);
    expect(find.textContaining('Card owned'), findsOneWidget);
    expect(find.textContaining('Card unowned'), findsOneWidget);
  });

  testWidgets('shows "Also best overall" when the same card wins both guaranteed pools', (tester) async {
    final winner = _candidate(cardId: 'shared', isOwned: true, savings: 300);
    final recommendation = MovieDealsRecommendation(
      candidates: [winner],
      rejectedCandidates: const [],
      bestGuaranteedOwned: winner,
      bestGuaranteedOverall: winner,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('BEST CARD YOU OWN'), findsOneWidget);
    expect(find.textContaining('Also best overall'), findsOneWidget);
    expect(find.textContaining('Card shared'), findsOneWidget);
  });

  testWidgets('falls back to a labeled potential candidate when no guaranteed winner exists', (tester) async {
    final potential = _candidate(
      cardId: 'potential-only',
      isOwned: true,
      savings: 6000,
      platformConfidence: MovieDealPlatformConfidence.notRequested,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [potential],
      rejectedCandidates: const [],
      bestPotentialOwned: potential,
      bestPotentialOverall: potential,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Card potential-only'), findsWidgets);
    expect(find.textContaining('Potential'), findsWidgets);
    // Must NOT be presented under the confirmed "BEST CARD YOU OWN" heading.
    expect(find.text('BEST CARD YOU OWN'), findsNothing);
  });

  testWidgets('shows a no-deal message when neither tier has a winner', (tester) async {
    const recommendation = MovieDealsRecommendation(candidates: [], rejectedCandidates: []);

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No verified eligible deal'), findsOneWidget);
  });

  testWidgets('shows a retryable unavailable message on repository failure', (tester) async {
    const recommendation = MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('a rewardMultiplier candidate renders its raw rate, never a computed rupee figure', (tester) async {
    final multiplier = _candidate(
      cardId: 'multiplier-card',
      isOwned: true,
      savings: 0,
      offerType: MovieDealOfferType.rewardMultiplier,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [multiplier],
      rejectedCandidates: const [],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('points program'), findsOneWidget);
    expect(find.textContaining('Save ₹0'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_results_test.dart`
Expected: FAIL — compile error, `movie_deals_results.dart` and `MovieDealsResults` don't exist yet.

- [ ] **Step 3: Write `movie_deals_results.dart`**

```dart
// lib/features/benefits/movie_deals/screens/movie_deals_results.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_ticket_request.dart';

/// Design spec §8's three-section layout: guaranteed owned/overall (falling
/// back to a labeled potential candidate when no guaranteed winner exists),
/// a distinct "Potential" section for anything the guaranteed tier didn't
/// surface, and rewardMultiplier candidates shown separately with their raw
/// rate — never mixed into either savings-based tier.
class MovieDealsResults extends ConsumerWidget {
  const MovieDealsResults({super.key, required this.request});

  final MovieTicketRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(movieDealsSearchProvider(request));
    return async.when(
      data: (recommendation) => _buildRecommendation(context, ref, recommendation),
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildRetryCard(context, ref),
    );
  }

  Widget _buildRecommendation(
      BuildContext context, WidgetRef ref, MovieDealsRecommendation recommendation) {
    if (recommendation.status == MovieDealsStatus.unavailable) {
      return _buildRetryCard(context, ref);
    }

    final rewardMultiplierCandidates =
        recommendation.candidates.where((c) => c.rule.offerType == MovieDealOfferType.rewardMultiplier).toList();

    final hasAnyGuaranteed =
        recommendation.bestGuaranteedOwned != null || recommendation.bestGuaranteedOverall != null;
    final hasAnyPotential =
        recommendation.bestPotentialOwned != null || recommendation.bestPotentialOverall != null;

    if (!hasAnyGuaranteed && !hasAnyPotential && rewardMultiplierCandidates.isEmpty) {
      return _buildNoDealCard(context);
    }

    final ownedWinner = recommendation.bestGuaranteedOwned ?? recommendation.bestPotentialOwned;
    final overallWinner = recommendation.bestGuaranteedOverall ?? recommendation.bestPotentialOverall;
    final ownedIsGuaranteed = recommendation.bestGuaranteedOwned != null;
    final overallIsGuaranteed = recommendation.bestGuaranteedOverall != null;
    final sharedWinner = ownedWinner != null &&
        overallWinner != null &&
        ownedWinner.cardId == overallWinner.cardId &&
        ownedWinner.benefitId == overallWinner.benefitId &&
        ownedIsGuaranteed == overallIsGuaranteed;

    Future<void> Function()? confirmCallbackFor(MovieDealCandidate candidate) {
      if (request.preferredPlatform == null) return null;
      if (candidate.platformConfidence == MovieDealPlatformConfidence.explicit) return null;
      return () => ref.read(movieDealsRepositoryProvider).confirmPlatform(
            benefitId: candidate.benefitId,
            platform: request.preferredPlatform!,
            userId: ref.read(currentUserProvider)!.id,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ownedWinner != null)
          _CandidatePanel(
            heading: ownedIsGuaranteed ? 'BEST CARD YOU OWN' : 'POTENTIAL — YOU OWN THIS CARD',
            candidate: ownedWinner,
            isPotential: !ownedIsGuaranteed,
            trailingLabel: sharedWinner ? 'Also best overall' : null,
            onConfirmPlatform: confirmCallbackFor(ownedWinner),
          ),
        if (ownedWinner != null && !sharedWinner) const SizedBox(height: 16),
        if (overallWinner != null && !sharedWinner)
          _CandidatePanel(
            heading: overallIsGuaranteed ? 'BEST CARD OVERALL' : 'POTENTIAL — BEST OVERALL',
            candidate: overallWinner,
            isOwned: false,
            isPotential: !overallIsGuaranteed,
            onConfirmPlatform: confirmCallbackFor(overallWinner),
          ),
        if (rewardMultiplierCandidates.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildRewardMultiplierSection(rewardMultiplierCandidates),
        ],
      ],
    );
  }

  Widget _buildRewardMultiplierSection(List<MovieDealCandidate> candidates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REWARD RATE — NOT A DIRECT DISCOUNT',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textMuted, fontSize: 10, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        ...candidates.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.surface3),
                ),
                child: Text(c.explanation, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
              ),
            )),
      ],
    );
  }

  Widget _buildNoDealCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.surface3),
      ),
      child: Text(
        'No verified eligible deal for this search. Try a different platform or ticket count.',
        style: GoogleFonts.inter(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildRetryCard(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Movie deals data is unavailable right now.',
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => ref.invalidate(movieDealsSearchProvider(request)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _CandidatePanel extends StatefulWidget {
  const _CandidatePanel({
    required this.heading,
    required this.candidate,
    this.isOwned,
    this.isPotential = false,
    this.trailingLabel,
    this.onConfirmPlatform,
  });

  final String heading;
  final MovieDealCandidate candidate;
  final bool? isOwned;
  final bool isPotential;
  final String? trailingLabel;
  final Future<void> Function()? onConfirmPlatform;

  @override
  State<_CandidatePanel> createState() => _CandidatePanelState();
}

class _CandidatePanelState extends State<_CandidatePanel> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final owned = widget.isOwned ?? candidate.isOwned;
    final borderColor = widget.isPotential
        ? AppColors.textMuted.withValues(alpha: 0.3)
        : (owned ? AppColors.neonCyan.withValues(alpha: 0.25) : AppColors.violet.withValues(alpha: 0.25));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(color: borderColor, width: 1.2),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.heading,
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 11, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            candidate.rule.cardName ?? candidate.title,
            style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (widget.isPotential)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Remaining balance not verified',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.warning),
                ),
              ),
            ),
          if (candidate.platformConfidence != MovieDealPlatformConfidence.explicit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Platform not confirmed for this offer',
                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
          Text(candidate.explanation, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            '₹${candidate.grossAmount.toStringAsFixed(0)} → ₹${candidate.finalAmount.toStringAsFixed(0)} · Save ₹${candidate.savings.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.neonCyan, fontSize: 13),
          ),
          if (widget.trailingLabel != null) ...[
            const SizedBox(height: 8),
            Text(widget.trailingLabel!, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
          ],
          if (widget.onConfirmPlatform != null && !_confirmed) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await widget.onConfirmPlatform!();
                if (mounted) setState(() => _confirmed = true);
              },
              child: const Text('Did this work here? Let us know'),
            ),
          ],
          if (_confirmed) ...[
            const SizedBox(height: 12),
            Text('Thanks — this helps other users.', style: GoogleFonts.inter(fontSize: 11, color: AppColors.neonCyan)),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_results_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Verify the Task 13 screen now compiles**

Run: `flutter analyze lib/features/benefits/movie_deals/`
Expected: No errors.

- [ ] **Step 6: Commit both Task 13 and Task 14 files together**

```bash
git add lib/features/benefits/movie_deals/screens/movie_deals_screen.dart lib/features/benefits/movie_deals/screens/movie_deals_results.dart test/features/benefits/movie_deals/movie_deals_results_test.dart
git commit -m "feat: add Movie Deals screen with guaranteed/potential/reward-rate result sections"
```

---

## Task 15: Wire the 5th navigation tab

**Files:**
- Modify: `lib/core/router/app_router.dart:17,19-24,76-81,129-134,206-211`

Re-verified against the current file content (read in full before writing this plan) — line numbers are accurate as of this plan's authoring.

- [ ] **Step 1: Update `_kTabPaths` and `_tabIndexFor`**

Replace lines 17-24:

```dart
const _kTabPaths = ['/app', '/app/cards', '/app/transactions', '/app/movie-deals', '/app/settings'];

int _tabIndexFor(String loc) {
  if (loc.startsWith('/app/cards')) return 1;
  if (loc.startsWith('/app/transactions')) return 2;
  if (loc.startsWith('/app/movie-deals')) return 3;
  if (loc.startsWith('/app/settings')) return 4;
  return 0;
}
```

- [ ] **Step 2: Add the import and update `_AppShell._bodies`**

Add near the top of the file, alongside the other feature screen imports (after line 12, before line 13):

```dart
import '../../features/benefits/movie_deals/screens/movie_deals_screen.dart';
```

Replace the `_bodies` list (was lines 76-81):

```dart
  static const _bodies = <Widget>[
    DashboardScreen(),
    CardsScreen(),
    TransactionsScreen(),
    MovieDealsScreen(),
    SettingsScreen(),
  ];
```

- [ ] **Step 3: Add the 5th item to `_SideRail._items`**

Replace the `_items` list in `_SideRail` (was lines 129-134):

```dart
  static const _items = [
    (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card, label: 'Cards'),
    (icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Ledger'),
    (icon: Icons.local_movies_outlined, activeIcon: Icons.local_movies, label: 'Movie Deals'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];
```

- [ ] **Step 4: Add the 5th item to `_BottomNav._items`**

Replace the `_items` list in `_BottomNav` (was lines 206-211) with the identical list from Step 3:

```dart
  static const _items = [
    (icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.credit_card_outlined, activeIcon: Icons.credit_card, label: 'Cards'),
    (icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: 'Ledger'),
    (icon: Icons.local_movies_outlined, activeIcon: Icons.local_movies, label: 'Movie Deals'),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];
```

- [ ] **Step 5: Verify it compiles and existing tests still pass**

Run: `flutter analyze lib/core/router/app_router.dart`
Expected: No errors.

Run: `flutter test`
Expected: All tests pass — this task adds no new automated test (router tab-index logic has no existing test coverage in this codebase to extend); verify manually per Task 16.

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat: add Movie Deals as 5th navigation tab"
```

---

## Task 16: Manual verification in the running app

**Files:**
- No code changes

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, exit code 0.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: No errors.

- [ ] **Step 3: Confirm the clean-database integration check from Task 8 still holds**

Run: `supabase db reset`
Expected: exits 0. This re-confirms the two P0 migration fixes from Task 8 didn't regress while later tasks were implemented.

- [ ] **Step 4: Launch the app and navigate to the new tab**

```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

Log in, then tap/click the new "Movie Deals" tab (5th item, film icon).

- [ ] **Step 5: Verify the input form renders per design spec §8**

Check: header with film icon + "MOVIE TICKET OPTIMIZER" + "AI RULE OPTIMIZATION ENGINE" badge; Tickets/Price fields; quick-select chips; Platform dropdown populated from `moviePlatformAliases` values (BookMyShow, Cinepolis, INOX, Moviemax, PVR, Zomato — alphabetically sorted); Cinema dropdown defaulting to "ANY CINEMA" with the "not yet supported" hint text visible; live total amount bar; "OPTIMIZE DEALS" button disabled until both fields are filled.

- [ ] **Step 6: Verify a real search against live data — confirm the guaranteed/potential split**

Enter 4 tickets, ₹300 price, select "BookMyShow" as platform. Submit. Confirm:
- If a `percentDiscount` benefit is mapped to any card (per Task 8's curated migration — check "25% off on movie tickets" → IDFC FIRST Millennia, or "Instant Discount on Bookmyshow" → Axis IndianOil), it should appear under "BEST CARD YOU OWN"/"BEST CARD OVERALL" with NO "Remaining balance not verified" chip.
- Any `bogo`/`fixedDiscount`/`milestone`/`annualAllowance` candidate for the same search must appear ONLY in a potential-labeled panel ("POTENTIAL — ..." heading, warning-colored "Remaining balance not verified" chip) — never under the plain "BEST CARD YOU OWN"/"BEST CARD OVERALL" heading. This is the concrete, visible manifestation of the guaranteed-tier data-availability limit from design spec §7.
- No raw exception/error text is shown to the user.

- [ ] **Step 7: Verify a rewardMultiplier candidate never shows a rupee savings figure**

Search with no platform selected, low ticket count. If a `rewardMultiplier` candidate appears (e.g. a card mapped to "3% Cashpoints on Paytm Purchases," if such a mapping exists), confirm it renders under "REWARD RATE — NOT A DIRECT DISCOUNT" with its raw rate text (e.g. "3.0 percent (points program, not a direct discount)"), never a "Save ₹X" line.

- [ ] **Step 8: Verify the crowd-source confirmation flow**

Search with a platform selected that no rule's `eligibleMoviePlatforms` recognizes (e.g. select "Zomato" against a `percentDiscount` card whose only partner is "BookMyShow"). Confirm the resulting candidate (if it appears in the potential section) shows "Did this work here? Let us know" — tap it, confirm it changes to "Thanks — this helps other users." with no error. Re-run the same search; the candidate's `platformConfidence` should now read as `communityConfirmed` rather than `notRequested`/`unconfirmed` (verify via a debug print or by checking the caveat chip text changes, if the UI distinguishes them visually — otherwise confirm via the repository test suite from Task 11, which already covers this at the unit level).

- [ ] **Step 9: Check responsive layout**

Resize the browser window to ~375px wide. Confirm the form fields stack sensibly and the result panels don't overflow horizontally.

- [ ] **Step 10: Report findings**

If any step above fails, this is the final task — do not mark it complete. Return to the relevant task's domain logic, repository query, or migration and fix the root cause (per superpowers:systematic-debugging), not just the symptom visible in the UI, then re-run this task's steps from the top.
