# Movie Deals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a "Movie Deals" screen that recommends the best card a user owns and the best card overall for buying movie tickets, reading real `benefits`/`card_benefit_mapping`/`user_cards`/`transactions`/`statement_milestone_cache` data, fixing the four root causes found in the prior engine (normalizer field-name mismatch, platform empty-set-as-wildcard, missing dual-panel UI, category miscoverage).

**Architecture:** Pure-Dart domain layer (rule model, normalizer, evaluator) with zero Flutter/Supabase dependency, fully unit-testable without a widget tree. A repository class in `lib/core/repositories/` (matching this codebase's existing pattern — plain class, constructor-injected `SupabaseClient`, wired via a single `Provider<T>` in `lib/core/providers/repository_providers.dart`) translates Supabase rows into the domain's input types. A `FutureProvider.family` (matching `dashboard_provider.dart`'s pattern) drives the search-and-recommend flow. A new screen reuses the main repo's `MovieAnalyzerTab` form/card visual design, wired to the corrected dual-panel data.

**Tech Stack:** Flutter, Dart, Riverpod (plain `Provider`/`FutureProvider`, no `@riverpod` codegen — this worktree doesn't use `riverpod_annotation`), Supabase Flutter, `flutter_test` (covers pure-Dart unit tests too), `go_router`.

**Design doc:** `docs/superpowers/specs/2026-08-02-movie-deals-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `lib/features/benefits/movie_deals/domain/movie_deal_rule.dart` | `MovieDealRule`, `MovieDealOfferType` enum, `MovieBenefitSource`, normalization result types |
| `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart` | Raw `value_config` JSON → `MovieDealRule`, full real-data field coverage |
| `lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart` | `MovieDealCandidate`, `RejectedMovieDealCandidate`, confidence enums, `MovieDealsRecommendation` |
| `lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart` | Eligibility, savings math, independent owned/overall ranking |
| `lib/features/benefits/movie_deals/domain/movie_ticket_request.dart` | `MovieTicketRequest` input type |
| `lib/core/repositories/movie_deals_repository.dart` | Read-only Supabase queries (widened fetch, confirmation aggregation) |
| `lib/core/providers/repository_providers.dart` | Modify: add `movieDealsRepositoryProvider` |
| `lib/features/benefits/movie_deals/providers/movie_deals_provider.dart` | `FutureProvider.family` wiring request → recommendation |
| `lib/features/benefits/movie_deals/screens/movie_deals_screen.dart` | Form (ported from `MovieAnalyzerTab`) + two-panel results |
| `lib/core/router/app_router.dart` | Modify: 5th tab wiring |
| `supabase/migrations/20260802100000_benefit_platform_confirmations.sql` | New additive table |
| `test/features/benefits/movie_deals/*_test.dart` | Unit/widget tests per component |

---

## Task 1: `MovieTicketRequest` and canonical rule model

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
    test('bogo rule stores per-transaction cap and monthly usage limit', () {
      final rule = MovieDealRule(
        benefitId: 'b1',
        catalogCardId: 'c1',
        title: 'Twin ticket treats',
        offerType: MovieDealOfferType.bogo,
        buyCount: 1,
        freeCount: 1,
        maximumDiscount: 500,
        cycleTransactionLimit: 2,
      );

      expect(rule.offerType, MovieDealOfferType.bogo);
      expect(rule.buyCount, 1);
      expect(rule.freeCount, 1);
      expect(rule.maximumDiscount, 500);
      expect(rule.cycleTransactionLimit, 2);
      expect(rule.platform, isNull);
    });

    test('rewardMultiplier rule stores rate, unit, and qualifying categories', () {
      final rule = MovieDealRule(
        benefitId: 'b2',
        catalogCardId: 'c2',
        title: '10X points on Dining, Movies, Grocery',
        offerType: MovieDealOfferType.rewardMultiplier,
        rewardMultiplierRate: 10.0,
        rewardMultiplierUnit: 'points per Rs.150',
        qualifyingCategories: const {'dining', 'movies', 'grocery'},
      );

      expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
      expect(rule.rewardMultiplierRate, 10.0);
      expect(rule.qualifyingCategories, contains('movies'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_test.dart`
Expected: FAIL — "Error: Couldn't resolve the package 'cardcompass'... movie_deal_rule.dart doesn't exist" (or equivalent compile error since the file does not exist yet).

- [ ] **Step 3: Write `movie_ticket_request.dart`**

```dart
// lib/features/benefits/movie_deals/domain/movie_ticket_request.dart

/// One search: how many tickets, at what price, on which platform/cinema.
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
/// [valueConfig] is the raw `benefits.value_config` JSONB for this row.
class MovieBenefitSource {
  MovieBenefitSource({
    required this.benefitId,
    required this.catalogCardId,
    required this.title,
    required Map<String, dynamic> valueConfig,
    this.sourceUrl,
    this.cardName,
    this.displayPriority = 0,
  }) : valueConfig = Map.unmodifiable(valueConfig);

  final String benefitId;
  final String catalogCardId;
  final String title;
  final Map<String, dynamic> valueConfig;
  final String? sourceUrl;
  final String? cardName;
  final int displayPriority;
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
/// unknown, never inferred from a default (design spec §4).
class MovieDealRule {
  MovieDealRule({
    required this.benefitId,
    required this.catalogCardId,
    required this.title,
    required this.offerType,
    this.sourceUrl,
    this.cardName,
    this.displayPriority = 0,
    this.platform,
    this.discountPercent,
    this.fixedAmount,
    this.maximumDiscount,
    this.buyCount,
    this.freeCount,
    this.cycleTransactionLimit,
    this.annualCap,
    this.milestoneThreshold,
    this.milestoneReward,
    this.rewardMultiplierRate,
    this.rewardMultiplierUnit,
    Set<String> qualifyingCategories = const {},
  }) : qualifyingCategories = Set.unmodifiable(qualifyingCategories);

  final String benefitId;
  final String catalogCardId;
  final String title;
  final String? sourceUrl;
  final String? cardName;
  final int displayPriority;
  final MovieDealOfferType offerType;

  /// Single platform this rule is explicitly tied to. Null means "not
  /// recorded" — NOT "matches every platform" (design spec §5 fixes the
  /// old empty-set-as-wildcard bug; platform confidence is computed by the
  /// evaluator per search, not stored here).
  final String? platform;

  final double? discountPercent;
  final double? fixedAmount;
  final double? maximumDiscount;

  /// bogo only. All real rows observed have buyCount=1, freeCount=1.
  final int? buyCount;
  final int? freeCount;

  /// "N times per month" usage limit — used by bogo and fixedDiscount rules.
  final int? cycleTransactionLimit;

  /// annualAllowance only — total ₹ available per calendar year.
  final double? annualCap;

  /// milestone only. Eligibility requires the PRIOR month's confirmed spend
  /// (from statement_milestone_cache) to already meet milestoneThreshold —
  /// never a forward-looking projection.
  final double? milestoneThreshold;
  final double? milestoneReward;

  /// rewardMultiplier only. Never converted to a ₹ estimate — there is no
  /// points-to-rupee exchange rate in the data (design spec §7 step 6).
  final double? rewardMultiplierRate;
  final String? rewardMultiplierUnit;
  final Set<String> qualifyingCategories;
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
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_ticket_request.dart lib/features/benefits/movie_deals/domain/movie_deal_rule.dart test/features/benefits/movie_deals/movie_deal_rule_test.dart
git commit -m "feat: add MovieDealRule and MovieTicketRequest models"
```

---

## Task 2: Normalizer — percentDiscount, fixedDiscount, bogo

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`

This task covers the 3 offer types whose field shapes were fully confirmed in design spec §4.3, rows 1–4, 7. Task 3 covers the remaining 3 (annualAllowance, milestone, rewardMultiplier) plus the currency_unit alias edge case, to keep each task's diff reviewable.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart';

MovieBenefitSource _source(Map<String, dynamic> config, {String? title}) =>
    MovieBenefitSource(
      benefitId: 'b1',
      catalogCardId: 'c1',
      title: title ?? 'Test benefit',
      valueConfig: config,
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
      expect(rule.platform, isNull);
    });

    test('platform field is captured when present', () {
      // Real row: "Instant Discount on Bookmyshow"
      final result = normalizeMovieDealRule(_source({
        'platform': 'Bookmyshow',
        'discount_type': 'percent',
        'discount_percent': 10.0,
      }));
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.platform, 'Bookmyshow');
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
    test('platform + monthly_cap + discount_amount normalizes correctly', () {
      // Real row: "BookMyShow Discount"
      final result = normalizeMovieDealRule(_source({
        'category': 'movie_tickets',
        'platform': 'BookMyShow',
        'monthly_cap': 1500.0,
        'is_recurring': true,
        'discount_amount': 1500.0,
      }));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.fixedDiscount);
      expect(rule.fixedAmount, 1500.0);
      expect(rule.maximumDiscount, 1500.0);
      expect(rule.platform, 'BookMyShow');
    });

    test('rejects a non-positive discount_amount', () {
      final result = normalizeMovieDealRule(
        _source({'discount_amount': 0}),
      );
      expect(result, isA<RejectedMovieDealRule>());
    });
  });

  group('normalizeMovieDealRule — bogo', () {
    test('discount_type=BOGO with per-transaction cap normalizes correctly', () {
      // Real row: "Twin ticket treats" — $500 off 2nd ticket, twice/month
      final result = normalizeMovieDealRule(_source({
        'category': 'movie_tickets',
        'discount_type': 'BOGO',
        'max_usage_per_month': 2,
        'max_discount_per_transaction': 500.0,
      }, title: 'Twin ticket treats'));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.bogo);
      expect(rule.buyCount, 1);
      expect(rule.freeCount, 1);
      expect(rule.maximumDiscount, 500.0);
      expect(rule.cycleTransactionLimit, 2);
    });

    test('second real bogo row (250 cap) normalizes correctly', () {
      // Real row: "Buy-1-Get-1 Movie Ticket Offer"
      final result = normalizeMovieDealRule(_source({
        'category': 'movie_tickets',
        'discount_type': 'BOGO',
        'max_usage_per_month': 2,
        'max_discount_per_transaction': 250.0,
      }));
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.maximumDiscount, 250.0);
      expect(rule.cycleTransactionLimit, 2);
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
/// Every branch here is derived from an actual row observed in
/// supabase/migrations/20260711043900_restore_reference_data.sql — see
/// design spec §4.3 for the full field-alias table. Unrecognized or
/// contradictory shapes are rejected with a diagnostic reason; nothing is
/// ever defaulted or invented.
RuleNormalizationResult normalizeMovieDealRule(MovieBenefitSource source) {
  final config = source.valueConfig;
  final platform = _string(config['platform']);

  final discountType = _string(config['discount_type'])?.toLowerCase();

  if (discountType == 'bogo') {
    return _normalizeBogo(source, platform);
  }

  final discountPercent = _number(config['discount_percent']);
  if (discountType == 'percent' || discountPercent != null) {
    return _normalizePercent(source, platform, discountPercent);
  }

  final discountAmount = _number(config['discount_amount']);
  if (discountAmount != null) {
    return _normalizeFixed(source, platform, discountAmount);
  }

  return const RejectedMovieDealRule(
    'No unambiguous movie offer type was supplied.',
  );
}

RuleNormalizationResult _normalizePercent(
  MovieBenefitSource source,
  String? platform,
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
    offerType: MovieDealOfferType.percentDiscount,
    platform: platform,
    discountPercent: discountPercent,
  ));
}

RuleNormalizationResult _normalizeFixed(
  MovieBenefitSource source,
  String? platform,
  double discountAmount,
) {
  if (discountAmount <= 0) {
    return const RejectedMovieDealRule(
      'A fixed-value offer requires a positive discount amount.',
    );
  }
  final cap = _number(source.valueConfig['monthly_cap']) ??
      _number(source.valueConfig['max_discount_per_transaction']);
  final cycleLimit = _integer(source.valueConfig['max_usage_per_month']);
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    offerType: MovieDealOfferType.fixedDiscount,
    platform: platform,
    fixedAmount: discountAmount,
    maximumDiscount: cap,
    cycleTransactionLimit: cycleLimit,
  ));
}

RuleNormalizationResult _normalizeBogo(
  MovieBenefitSource source,
  String? platform,
) {
  final cap = _number(source.valueConfig['max_discount_per_transaction']);
  final cycleLimit = _integer(source.valueConfig['max_usage_per_month']);
  if (cap == null || cap <= 0) {
    return const RejectedMovieDealRule(
      'A BOGO offer requires a positive per-transaction discount cap.',
    );
  }
  if (cycleLimit == null || cycleLimit <= 0) {
    return const RejectedMovieDealRule(
      'A BOGO offer requires a positive monthly usage limit.',
    );
  }
  return AcceptedMovieDealRule(MovieDealRule(
    benefitId: source.benefitId,
    catalogCardId: source.catalogCardId,
    title: source.title,
    sourceUrl: source.sourceUrl,
    cardName: source.cardName,
    displayPriority: source.displayPriority,
    offerType: MovieDealOfferType.bogo,
    platform: platform,
    buyCount: 1,
    freeCount: 1,
    maximumDiscount: cap,
    cycleTransactionLimit: cycleLimit,
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart
git commit -m "feat: normalize percentDiscount, fixedDiscount, bogo movie deal rules"
```

---

## Task 3: Normalizer — annualAllowance, milestone, rewardMultiplier

**Files:**
- Modify: `lib/features/benefits/movie_deals/domain/movie_deal_rule.dart` (add remaining fields — already added in Task 1, no change needed here; this task only adds normalizer branches)
- Modify: `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart:1-27` (the top-level dispatch in `normalizeMovieDealRule`)
- Modify: `test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`

- [ ] **Step 1: Add the failing tests**

Append to `test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`, inside `main()`, after the existing groups:

```dart
  group('normalizeMovieDealRule — annualAllowance', () {
    test('unit=fixed with annual_cap and reward_value normalizes correctly', () {
      // Real row: "SBI Card ELITE Free Movie Tickets"
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
    test('reward_value + threshold_amount + milestone_type normalizes correctly', () {
      // Real row: "Monthly Vouchers on Spends"
      final result = normalizeMovieDealRule(_source({
        'reward_value': 500.0,
        'milestone_type': 'monthly',
        'threshold_amount': 80000.0,
      }));
      expect(result, isA<AcceptedMovieDealRule>());
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.milestone);
      expect(rule.milestoneReward, 500.0);
      expect(rule.milestoneThreshold, 80000.0);
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

    test('percent-based cashback multiplier with movies in category list normalizes correctly', () {
      // Real row: "3% Cashpoints on Paytm Purchases"
      final result = normalizeMovieDealRule(_source({
        'unit': 'percent',
        'category': 'utilities,movies',
        'base_rate': 3.0,
        'is_recurring': true,
      }));
      final rule = (result as AcceptedMovieDealRule).rule;
      expect(rule.offerType, MovieDealOfferType.rewardMultiplier);
      expect(rule.rewardMultiplierRate, 3.0);
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
Expected: FAIL — the new tests expect `MovieDealOfferType.annualAllowance`, `.milestone`, `.rewardMultiplier` branches that `normalizeMovieDealRule` doesn't yet produce (falls through to the "no unambiguous offer type" rejection).

- [ ] **Step 3: Add the three branches**

In `lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart`, replace the body of `normalizeMovieDealRule`:

```dart
RuleNormalizationResult normalizeMovieDealRule(MovieBenefitSource source) {
  final config = source.valueConfig;
  final platform = _string(config['platform']);

  final discountType = _string(config['discount_type'])?.toLowerCase();
  if (discountType == 'bogo') {
    return _normalizeBogo(source, platform);
  }

  final discountPercent = _number(config['discount_percent']);
  if (discountType == 'percent' || discountPercent != null) {
    return _normalizePercent(source, platform, discountPercent);
  }

  final unit = _string(config['unit'])?.toLowerCase();
  final threshold = _number(config['threshold_amount']);
  final milestoneType = _string(config['milestone_type']);
  if (milestoneType != null || threshold != null) {
    return _normalizeMilestone(source);
  }

  final category = _string(config['category'])?.toLowerCase() ?? '';
  final mentionsMovies = category.split(',').map((c) => c.trim()).contains('movies');
  final rate = _number(config['multiplier']) ?? _number(config['base_rate']);
  if (mentionsMovies && rate != null && unit != null && unit != 'fixed') {
    return _normalizeRewardMultiplier(source, unit, rate, category);
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
    return _normalizeFixed(source, platform, discountAmount);
  }

  return const RejectedMovieDealRule(
    'No unambiguous movie offer type was supplied.',
  );
}

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
    offerType: MovieDealOfferType.annualAllowance,
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
    offerType: MovieDealOfferType.milestone,
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
    offerType: MovieDealOfferType.rewardMultiplier,
    rewardMultiplierRate: rate,
    rewardMultiplierUnit: unit,
    qualifyingCategories: categories,
  ));
}
```

Leave `_normalizePercent`, `_normalizeFixed`, `_normalizeBogo`, and the `_number`/`_integer`/`_string` helpers from Task 2 unchanged below this.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart`
Expected: PASS (16 tests total)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart test/features/benefits/movie_deals/movie_deal_rule_normalizer_test.dart
git commit -m "feat: normalize annualAllowance, milestone, rewardMultiplier deal rules"
```

---

## Task 4: Fixture regression test against every real seed-data row

**Files:**
- Test: `test/features/benefits/movie_deals/movie_benefit_fixture_test.dart`

This is the regression guard against repeating root causes 1 and 4 — it hardcodes every real `value_config` shape found in `supabase/migrations/20260711043900_restore_reference_data.sql` and asserts each is either accepted with the expected offer type, or rejected with a reason. No network calls, no reading the SQL file at test runtime.

- [ ] **Step 1: Write the test**

```dart
// test/features/benefits/movie_deals/movie_benefit_fixture_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule_normalizer.dart';

MovieBenefitSource _source(Map<String, dynamic> config, String title) =>
    MovieBenefitSource(
      benefitId: 'fixture',
      catalogCardId: 'fixture-card',
      title: title,
      valueConfig: config,
    );

void main() {
  group('production-format fixture regression', () {
    final fixtures = <String, (Map<String, dynamic>, MovieDealOfferType)>{
      '25% Off on Movie Tickets': (
        {'discount_type': 'percent', 'discount_percent': 25.0},
        MovieDealOfferType.percentDiscount,
      ),
      'SBI Card ELITE Free Movie Tickets': (
        {'unit': 'fixed', 'category': 'movie_tickets', 'annual_cap': 6000.0, 'reward_value': 6000.0},
        MovieDealOfferType.annualAllowance,
      ),
      'Twin ticket treats': (
        {'category': 'movie_tickets', 'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 500.0},
        MovieDealOfferType.bogo,
      ),
      'Buy-1-Get-1 Movie Ticket Offer': (
        {'category': 'movie_tickets', 'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 250.0},
        MovieDealOfferType.bogo,
      ),
      'BookMyShow Discount': (
        {'category': 'movie_tickets', 'platform': 'BookMyShow', 'monthly_cap': 1500.0, 'is_recurring': true, 'currency_unit': 1500.0, 'discount_amount': 1500.0},
        MovieDealOfferType.fixedDiscount,
      ),
      'Instant Discount on Bookmyshow': (
        {'category': 'movie_tickets', 'platform': 'Bookmyshow', 'discount_type': 'percent', 'discount_percent': 10.0},
        MovieDealOfferType.percentDiscount,
      ),
      'Monthly Vouchers on Spends': (
        {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0},
        MovieDealOfferType.milestone,
      ),
      'Free Movie Tickets (lifestyle-tagged variant)': (
        {'unit': 'fixed', 'currency_unit': 6000.0},
        MovieDealOfferType.annualAllowance,
      ),
      '10X Reward Points on Dining, Movies, Departmental Stores and Grocery': (
        {'unit': 'points per Rs.150', 'category': 'dining,movies,departmental_stores,grocery', 'multiplier': 10.0},
        MovieDealOfferType.rewardMultiplier,
      ),
      '3% Cashpoints on Paytm Purchases': (
        {'unit': 'percent', 'category': 'utilities,movies', 'base_rate': 3.0, 'monthly_cap': 500.0, 'is_recurring': true},
        MovieDealOfferType.rewardMultiplier,
      ),
      '5% Cashpoints on Paytm': (
        {'unit': 'percent', 'category': 'recharge,utilities,travel,movies', 'base_rate': 5.0, 'monthly_cap_points': 1500},
        MovieDealOfferType.rewardMultiplier,
      ),
    };

    fixtures.forEach((title, fixture) {
      final (config, expectedType) = fixture;
      test('$title normalizes as $expectedType', () {
        final result = normalizeMovieDealRule(_source(config, title));
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

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_benefit_fixture_test.dart`
Expected: If Tasks 2–3 were completed correctly, this should already PASS (12 tests) — it's a regression guard over existing behavior, not new functionality. Run it to confirm.

- [ ] **Step 3: If any fixture fails, fix the normalizer (not the fixture)**

Any fixture mismatch here means a real production row would be silently mishandled — do not adjust the expected value to match broken behavior. Trace which branch of `normalizeMovieDealRule` the failing config falls into and fix that branch.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_benefit_fixture_test.dart`
Expected: PASS (12 tests)

- [ ] **Step 5: Commit**

```bash
git add test/features/benefits/movie_deals/movie_benefit_fixture_test.dart
git commit -m "test: add production-format fixture regression for movie deal normalizer"
```

---

## Task 5: Candidate/recommendation models and confidence enums

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_candidate_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/benefits/movie_deals/movie_deal_candidate_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';

void main() {
  test('MovieDealsRecommendation exposes independent bestOwned/bestOverall', () {
    final rule = MovieDealRule(
      benefitId: 'b1',
      catalogCardId: 'c1',
      title: 'Test',
      offerType: MovieDealOfferType.percentDiscount,
      discountPercent: 25,
    );
    final owned = MovieDealCandidate(
      cardId: 'c1',
      benefitId: 'b1',
      title: 'Test',
      rule: rule,
      isOwned: true,
      grossAmount: 1000,
      savings: 250,
      finalAmount: 750,
      usageConfidence: MovieDealUsageConfidence.unverified,
      platformConfidence: MovieDealPlatformConfidence.explicit,
      explanation: 'saves 250',
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [owned],
      rejectedCandidates: const [],
      bestOwned: owned,
      bestOverall: owned,
    );

    expect(recommendation.bestOwned, owned);
    expect(recommendation.bestOverall, owned);
    expect(recommendation.status, MovieDealsStatus.available);
  });

  test('unavailable status can be constructed without owned/overall winners', () {
    const recommendation = MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );
    expect(recommendation.bestOwned, isNull);
    expect(recommendation.bestOverall, isNull);
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

/// Design spec §5. Computed per evaluation — depends on both the rule and
/// the specific platform searched for, never stored statically on the rule.
enum MovieDealPlatformConfidence { explicit, communityConfirmed, unconfirmed }

enum MovieDealsStatus { available, unavailable }

/// Context supplied by the repository for one catalog card. Contains only
/// already-observed state, keeping the evaluator pure.
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

  /// Platforms with >=1 crowd-sourced confirmation for this benefit
  /// (design spec §6).
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

class MovieDealsRecommendation {
  const MovieDealsRecommendation({
    required this.candidates,
    required this.rejectedCandidates,
    this.status = MovieDealsStatus.available,
    this.bestOwned,
    this.bestOverall,
  });

  final List<MovieDealCandidate> candidates;
  final List<RejectedMovieDealCandidate> rejectedCandidates;
  final MovieDealsStatus status;
  final MovieDealCandidate? bestOwned;
  final MovieDealCandidate? bestOverall;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_candidate_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart test/features/benefits/movie_deals/movie_deal_candidate_test.dart
git commit -m "feat: add MovieDealCandidate and recommendation models"
```

---

## Task 6: Evaluator — eligibility, savings math, independent ranking

**Files:**
- Create: `lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart`
- Test: `test/features/benefits/movie_deals/movie_deal_evaluator_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_evaluator.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';

MovieDealRule _bogoRule({String cardId = 'c1', String? platform}) => MovieDealRule(
      benefitId: 'b-bogo',
      catalogCardId: cardId,
      title: 'Twin ticket treats',
      offerType: MovieDealOfferType.bogo,
      platform: platform,
      buyCount: 1,
      freeCount: 1,
      maximumDiscount: 500,
      cycleTransactionLimit: 2,
    );

MovieDealRule _percentRule({String cardId = 'c2', double percent = 10}) => MovieDealRule(
      benefitId: 'b-percent',
      catalogCardId: cardId,
      title: '10% off',
      offerType: MovieDealOfferType.percentDiscount,
      discountPercent: percent,
    );

void main() {
  final today = DateTime(2026, 8, 2);

  group('bogo savings math', () {
    test('per-transaction cap of 500 clamps a higher-priced pair correctly', () {
      // 2 tickets @ 400 = 800 gross. Second ticket "free" would be 400, but
      // the rule caps the discount at 500 per transaction — 400 < 500, so
      // the full second-ticket price is saved (design spec §4.3 bogo row).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 400),
        rules: [_bogoRule()],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestOwned, isNotNull);
      expect(result.bestOwned!.savings, 400);
      expect(result.bestOwned!.finalAmount, 400);
    });

    test('per-transaction cap of 500 clamps when second ticket exceeds the cap', () {
      // 2 tickets @ 600 = 1200 gross. Second ticket would be 600, but the
      // cap is 500 — savings clamp to 500, not the full ticket price.
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 600),
        rules: [_bogoRule()],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestOwned!.savings, 500);
      expect(result.bestOwned!.finalAmount, 700);
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
      expect(result.bestOwned!.savings, 120);
      expect(result.bestOwned!.finalAmount, 1080);
    });
  });

  group('independent owned/overall ranking', () {
    test('keeps owned and overall winners independent — no ownership bonus', () {
      // Owned card has a worse deal (10%); unowned card has a better one (bogo).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [
          _percentRule(cardId: 'owned-card', percent: 10),
          _bogoRule(cardId: 'unowned-card'),
        ],
        contexts: {
          'owned-card': const MovieDealContext(isOwned: true),
          'unowned-card': const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.bestOwned!.cardId, 'owned-card');
      expect(result.bestOverall!.cardId, 'unowned-card');
      // The unowned card's bogo deal (saves 300 on a 600 gross) beats the
      // owned card's 10% deal (saves 60) — ownership never overrides this.
      expect(result.bestOverall!.savings, greaterThan(result.bestOwned!.savings));
    });

    test('shared winner appears as the same candidate in both pools', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [_bogoRule(cardId: 'c1')],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestOwned!.cardId, result.bestOverall!.cardId);
      expect(result.bestOwned!.benefitId, result.bestOverall!.benefitId);
    });
  });

  group('platform eligibility', () {
    test('a rule tied to a specific platform is rejected for a different platform search', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(
          numberOfTickets: 1,
          pricePerTicket: 300,
          preferredPlatform: 'PVR',
        ),
        rules: [_bogoRule(platform: 'BookMyShow')],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.candidates, isEmpty);
      expect(result.rejectedCandidates, hasLength(1));
      expect(result.rejectedCandidates.first.reason, isNotEmpty);
    });

    test('a rule with no recorded platform still surfaces, flagged unconfirmed', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(
          numberOfTickets: 1,
          pricePerTicket: 300,
          preferredPlatform: 'PVR',
        ),
        rules: [_percentRule()], // no platform set
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.platformConfidence,
          MovieDealPlatformConfidence.unconfirmed);
    });

    test('a rule with no recorded platform but a crowd confirmation is communityConfirmed', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(
          numberOfTickets: 1,
          pricePerTicket: 300,
          preferredPlatform: 'PVR',
        ),
        rules: [_percentRule()],
        contexts: {
          'c2': const MovieDealContext(isOwned: true, confirmedPlatforms: {'PVR'}),
        },
        now: today,
      );
      expect(result.candidates.first.platformConfidence,
          MovieDealPlatformConfidence.communityConfirmed);
    });

    test('any-platform search (no preferredPlatform) treats every rule as explicit', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [_percentRule()],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.candidates.first.platformConfidence,
          MovieDealPlatformConfidence.explicit);
    });

    test('confidence tie-break: explicit match beats unconfirmed at equal savings', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(
          numberOfTickets: 1,
          pricePerTicket: 300,
          preferredPlatform: 'BookMyShow',
        ),
        rules: [
          _percentRule(cardId: 'explicit-card', percent: 10)
              .let((r) => MovieDealRule(
                    benefitId: r.benefitId,
                    catalogCardId: r.catalogCardId,
                    title: r.title,
                    offerType: r.offerType,
                    discountPercent: r.discountPercent,
                    platform: 'BookMyShow',
                  )),
          _percentRule(cardId: 'unconfirmed-card', percent: 10),
        ],
        contexts: {
          'explicit-card': const MovieDealContext(isOwned: false),
          'unconfirmed-card': const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.bestOverall!.cardId, 'explicit-card');
    });
  });

  group('milestone eligibility', () {
    test('milestone with confirmed prior-month spend at threshold is eligible', () {
      final rule = MovieDealRule(
        benefitId: 'b-milestone',
        catalogCardId: 'c3',
        title: 'Monthly Vouchers',
        offerType: MovieDealOfferType.milestone,
        milestoneThreshold: 80000,
        milestoneReward: 500,
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [rule],
        contexts: {
          'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000),
        },
        now: today,
      );
      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.savings, 300); // capped by eligible spend
    });

    test('milestone with no cached spend is unavailable, not eligible', () {
      final rule = MovieDealRule(
        benefitId: 'b-milestone',
        catalogCardId: 'c3',
        title: 'Monthly Vouchers',
        offerType: MovieDealOfferType.milestone,
        milestoneThreshold: 80000,
        milestoneReward: 500,
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [rule],
        contexts: {'c3': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.candidates, isEmpty);
      expect(result.rejectedCandidates, hasLength(1));
    });

    test('milestone with prior-month spend below threshold is not eligible', () {
      final rule = MovieDealRule(
        benefitId: 'b-milestone',
        catalogCardId: 'c3',
        title: 'Monthly Vouchers',
        offerType: MovieDealOfferType.milestone,
        milestoneThreshold: 80000,
        milestoneReward: 500,
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [rule],
        contexts: {
          'c3': const MovieDealContext(isOwned: true, milestoneSpend: 50000),
        },
        now: today,
      );
      expect(result.candidates, isEmpty);
    });
  });

  group('rewardMultiplier never gets a computed rupee savings figure', () {
    test('rewardMultiplier candidate has zero computed savings and is ranked last', () {
      final multiplierRule = MovieDealRule(
        benefitId: 'b-mult',
        catalogCardId: 'c4',
        title: '10X points',
        offerType: MovieDealOfferType.rewardMultiplier,
        rewardMultiplierRate: 10,
        rewardMultiplierUnit: 'points per Rs.150',
        qualifyingCategories: const {'movies'},
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [multiplierRule, _bogoRule(cardId: 'c5')],
        contexts: {
          'c4': const MovieDealContext(isOwned: true),
          'c5': const MovieDealContext(isOwned: true),
        },
        now: today,
      );
      // bogo (real rupee savings) must outrank rewardMultiplier (no rupee figure)
      expect(result.bestOwned!.rule.offerType, MovieDealOfferType.bogo);
      final multiplierCandidate =
          result.candidates.firstWhere((c) => c.rule.offerType == MovieDealOfferType.rewardMultiplier);
      expect(multiplierCandidate.savings, 0);
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
      expect(result.candidates.first.savings, lessThanOrEqualTo(100));
      expect(result.candidates.first.savings, greaterThanOrEqualTo(0));
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
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
import 'movie_ticket_request.dart';

export 'movie_deal_candidate.dart';

/// Evaluates every rule against one request, returning independently-ranked
/// owned and overall recommendations. Design spec §7 — ownership is never a
/// scoring bonus; the two pools are ranked from the same sorted candidate
/// list, just filtered differently.
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

  candidates.sort(_compareCandidates);
  final owned = candidates.where((c) => c.isOwned).toList();
  return MovieDealsRecommendation(
    candidates: candidates,
    rejectedCandidates: rejected,
    bestOwned: owned.isEmpty ? null : owned.first,
    bestOverall: candidates.isEmpty ? null : candidates.first,
  );
}

String? _ineligibilityReason(
  MovieDealRule rule,
  MovieTicketRequest request,
  MovieDealContext context,
  DateTime now,
) {
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
      rule.cycleTransactionLimit != null &&
      context.usageConfidence == MovieDealUsageConfidence.verified &&
      context.usedTransactions >= rule.cycleTransactionLimit!) {
    return 'Monthly usage limit has been reached.';
  }

  return null;
}

/// A rule tied to a specific platform must match the search exactly. A rule
/// with no recorded platform, or a search with no preferred platform, always
/// passes eligibility — platform CONFIDENCE (not eligibility) is what
/// distinguishes a confirmed match from an unconfirmed one (design spec §5).
bool _platformMatches(MovieDealRule rule, MovieTicketRequest request) {
  if (rule.platform == null) return true;
  if (request.preferredPlatform == null) return true;
  return rule.platform!.toLowerCase() == request.preferredPlatform!.toLowerCase();
}

MovieDealPlatformConfidence _platformConfidence(
  MovieDealRule rule,
  MovieTicketRequest request,
  MovieDealContext context,
) {
  if (request.preferredPlatform == null) {
    return MovieDealPlatformConfidence.explicit;
  }
  if (rule.platform != null &&
      rule.platform!.toLowerCase() == request.preferredPlatform!.toLowerCase()) {
    return MovieDealPlatformConfidence.explicit;
  }
  final confirmed = context.confirmedPlatforms
      .any((p) => p.toLowerCase() == request.preferredPlatform!.toLowerCase());
  return confirmed
      ? MovieDealPlatformConfidence.communityConfirmed
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
      final perPairDiscount = rule.maximumDiscount != null
          ? (price < rule.maximumDiscount! ? price : rule.maximumDiscount!)
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
  if (rule.maximumDiscount != null &&
      rule.offerType != MovieDealOfferType.bogo &&
      savings > rule.maximumDiscount!) {
    savings = rule.maximumDiscount!;
  }
  return savings.clamp(0, gross).toDouble();
}

String _explanation(MovieDealRule rule, double savings,
        MovieDealUsageConfidence confidence) =>
    switch (rule.offerType) {
      MovieDealOfferType.rewardMultiplier =>
        '${rule.rewardMultiplierRate} ${rule.rewardMultiplierUnit} (points program, not a direct discount).',
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
  result = _usageConfidenceRank(right.usageConfidence)
      .compareTo(_usageConfidenceRank(left.usageConfidence));
  if (result != 0) return result;
  result = right.rule.displayPriority.compareTo(left.rule.displayPriority);
  if (result != 0) return result;
  result = left.cardId.compareTo(right.cardId);
  return result != 0 ? result : left.benefitId.compareTo(right.benefitId);
}

int _platformConfidenceRank(MovieDealPlatformConfidence confidence) =>
    switch (confidence) {
      MovieDealPlatformConfidence.explicit => 2,
      MovieDealPlatformConfidence.communityConfirmed => 1,
      MovieDealPlatformConfidence.unconfirmed => 0,
    };

int _usageConfidenceRank(MovieDealUsageConfidence confidence) =>
    switch (confidence) {
      MovieDealUsageConfidence.verified => 2,
      MovieDealUsageConfidence.unverified => 1,
      MovieDealUsageConfidence.unavailable => 0,
    };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deal_evaluator_test.dart`
Expected: PASS (14 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/benefits/movie_deals/domain/movie_deal_evaluator.dart test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
git commit -m "feat: evaluate movie deals with platform confidence and independent ranking"
```

---

## Task 7: Crowd-source confirmation table migration

**Files:**
- Create: `supabase/migrations/20260802100000_benefit_platform_confirmations.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Design spec §6. Additive only — does not alter benefits, card_benefit_mapping,
-- user_cards, or transactions. Records a user's report that a benefit worked
-- at a specific platform, when the benefit itself has no recorded platform.
create table if not exists benefit_platform_confirmations (
  id           uuid primary key default gen_random_uuid(),
  benefit_id   uuid not null references benefits(benefit_id),
  platform     text not null,
  user_id      uuid not null references auth.users(id),
  confirmed_at timestamptz not null default now()
);

create index if not exists idx_benefit_platform_confirmations_lookup
  on benefit_platform_confirmations(benefit_id, platform);

alter table benefit_platform_confirmations enable row level security;

-- Authenticated users can insert their own confirmation. No update/delete
-- from the client — confirmations are immutable reports.
create policy "authenticated insert own confirmation"
  on benefit_platform_confirmations for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Aggregated counts need to be readable to compute platformConfidence.
create policy "authenticated read all confirmations"
  on benefit_platform_confirmations for select
  to authenticated
  using (true);
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push`
Expected: Migration applies without error. If applying manually, paste the SQL into the Supabase dashboard → SQL editor and run it.

- [ ] **Step 3: Verify the table exists**

Run: `supabase db diff --schema public 2>&1 | grep benefit_platform_confirmations`
Expected: no output (diff is empty — migration matches the live schema, meaning it applied cleanly). If the table was created via manual SQL editor paste instead of `db push`, this step may show a diff until `supabase migration repair` is run — resolve any diff before continuing.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260802100000_benefit_platform_confirmations.sql
git commit -m "feat: add benefit_platform_confirmations table"
```

---

## Task 8: Repository — widened fetch, snapshot loading, confirmation aggregation

**Files:**
- Create: `lib/core/repositories/movie_deals_repository.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_repository_test.dart`

The repository is tested against a fake `MovieDealsDataSource` (an interface, not a live Supabase client) so it runs with no network/credentials — matching the pattern the design spec's verification strategy calls for.

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
}

void main() {
  group('MovieDealsSupabaseRepository', () {
    test('owned status is matched via catalog_card_id, not user_card id', () {
      // Verifies the identity boundary: user_cards.catalog_card_id must
      // match card_benefit_mapping.card_id (= card_catalog.id), never
      // user_cards.id itself.
      final dataSource = _FakeDataSource(
        benefits: [
          {'benefit_id': 'b1', 'title': 'Test', 'value_config': {'discount_type': 'percent', 'discount_percent': 25.0}, 'source_url': null},
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
        expect(snapshot.contexts['catalog-card-1']?.isOwned, isTrue);
      });
    });

    test('capped usage is unverified when matching transaction metadata lacks numeric ticket_count', () async {
      final dataSource = _FakeDataSource(
        benefits: [
          {'benefit_id': 'b1', 'title': 'BOGO', 'value_config': {'discount_type': 'BOGO', 'max_usage_per_month': 2, 'max_discount_per_transaction': 500.0}, 'source_url': null},
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
          // Matches platform but has no ticket_count in metadata.
          {'user_card_id': 'user-card-1', 'merchant_name': 'BookMyShow', 'metadata': <String, dynamic>{}},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
      );
      expect(snapshot.contexts['catalog-card-1']?.usageConfidence,
          isNot(equals(MovieDealUsageConfidenceForTest.verified)));
    });

    test('absent milestone cache leaves milestoneSpend null, not zero', () async {
      final dataSource = _FakeDataSource(
        benefits: [
          {'benefit_id': 'b1', 'title': 'Milestone', 'value_config': {'reward_value': 500.0, 'milestone_type': 'monthly', 'threshold_amount': 80000.0}, 'source_url': null},
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
        milestones: const [], // no cache row for this card
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
      );
      expect(snapshot.contexts['catalog-card-1']?.milestoneSpend, isNull);
    });

    test('confirmed platforms are aggregated per benefit', () async {
      final dataSource = _FakeDataSource(
        benefits: [
          {'benefit_id': 'b1', 'title': 'No platform recorded', 'value_config': {'discount_type': 'percent', 'discount_percent': 25.0}, 'source_url': null},
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
        confirmations: [
          {'benefit_id': 'b1', 'platform': 'PVR'},
          {'benefit_id': 'b1', 'platform': 'PVR'},
        ],
      );
      final repository = MovieDealsSupabaseRepository(dataSource);

      final snapshot = await repository.loadSnapshot(
        'user1',
        const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
      );
      expect(snapshot.contexts['catalog-card-1']?.confirmedPlatforms, contains('PVR'));
    });
  });
}

// Local alias so this test file doesn't need to import the domain enum
// directly if it isn't already exported from the repository file — remove
// this if movie_deals_repository.dart already re-exports
// MovieDealUsageConfidence (it should, via `export`).
typedef MovieDealUsageConfidenceForTest = MovieDealUsageConfidence;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: FAIL — compile error, `movie_deals_repository.dart` doesn't exist yet.

- [ ] **Step 3: Write the repository**

```dart
// lib/core/repositories/movie_deals_repository.dart
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';

export 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';

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

/// The small read surface used by [MovieDealsSupabaseRepository]. Kept
/// separate from Supabase query builders so the repository is deterministic
/// to unit-test without credentials.
abstract interface class MovieDealsDataSource {
  /// Design spec §4.1 — widened beyond benefit_category='entertainment' to
  /// also catch rows tagged lifestyle/dining/rewards/offers that mention
  /// movies (root cause 4: category miscoverage).
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
}

class MovieDealsSupabaseRepository implements MovieDealsRepository {
  MovieDealsSupabaseRepository(this._dataSource);

  final MovieDealsDataSource _dataSource;

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
      final confirmedPlatforms = entry.value
          .map((source) => confirmedPlatformsByBenefit[source.benefitId] ?? <String>{})
          .expand((set) => set)
          .toSet();
      contexts[entry.key] = MovieDealContext(
        isOwned: isOwned,
        usageConfidence: verified
            ? MovieDealUsageConfidence.verified
            : MovieDealUsageConfidence.unverified,
        usedTickets: usedTickets,
        usedTransactions: verified ? matching.length : 0,
        milestoneSpend: spendByCatalogCardId[entry.key],
        confirmedPlatforms: confirmedPlatforms,
      );
    }
    return MovieDealsSnapshot(sources: sources, contexts: contexts);
  }
}

class SupabaseMovieDealsDataSource implements MovieDealsDataSource {
  SupabaseMovieDealsDataSource(this._client);

  final SupabaseClient _client;

  static const _movieKeywords = ['movie', 'cinema', 'bookmyshow', 'pvr', 'inox', 'cinepolis'];

  @override
  Future<List<Map<String, dynamic>>> loadMovieRelatedBenefits() async {
    // Design spec §4.1 — widened fetch: entertainment category OR any
    // movie/cinema keyword in category/title/description. Fixes root
    // cause 4 (31 real movie-related rows tagged outside 'entertainment').
    final keywordFilter = _movieKeywords
        .map((k) => 'title.ilike.%$k%,description.ilike.%$k%')
        .join(',');
    final rows = _rows(await _client
        .from('benefits')
        .select('benefit_id, title, value_config, source_url')
        .eq('is_active', true)
        .or('benefit_category.eq.entertainment,$keywordFilter'));
    return rows;
  }

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

  @override
  Future<List<Map<String, dynamic>>> loadConfirmations(
          List<String> benefitIds) async =>
      benefitIds.isEmpty
          ? const []
          : _rows(await _client
              .from('benefit_platform_confirmations')
              .select('benefit_id, platform')
              .inFilter('benefit_id', benefitIds));
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
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/core/repositories/movie_deals_repository.dart test/features/benefits/movie_deals/movie_deals_repository_test.dart
git commit -m "feat: add movie deals repository with widened fetch and confirmation aggregation"
```

---

## Task 9: Wire the repository provider and search FutureProvider

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

- [ ] **Step 3: Add `movieDealsRepositoryProvider` to `repository_providers.dart`**

Read `lib/core/providers/repository_providers.dart` first — it currently defines `cardsRepositoryProvider`, `transactionsRepositoryProvider`, `statementsRepositoryProvider`. Add a fourth provider following the exact same shape:

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

/// Runs one Movie Deals search: loads a snapshot, normalizes every source,
/// evaluates accepted rules, and returns a dual owned/overall recommendation.
/// Returns an explicit MovieDealsStatus.unavailable rather than an empty
/// no-deal result on any failure (design spec §11).
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
    final repository = ref.read(movieDealsRepositoryProvider);
    final snapshot = await repository.loadSnapshot(user.id, request);

    final rules = <MovieDealRule>[];
    for (final source in snapshot.sources) {
      final normalized = normalizeMovieDealRule(source);
      if (normalized case AcceptedMovieDealRule(:final rule)) {
        rules.add(rule);
      }
    }

    return evaluateMovieDeals(
      request: request,
      rules: rules,
      contexts: snapshot.contexts,
      now: DateTime.now(),
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

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_provider_test.dart`
Expected: PASS (1 test)

- [ ] **Step 6: Commit**

```bash
git add lib/core/providers/repository_providers.dart lib/features/benefits/movie_deals/providers/movie_deals_provider.dart test/features/benefits/movie_deals/movie_deals_provider_test.dart
git commit -m "feat: wire movie deals repository provider and search FutureProvider"
```

---

## Task 10: Movie Deals screen — form (ported from MovieAnalyzerTab)

**Files:**
- Create: `lib/features/benefits/movie_deals/screens/movie_deals_screen.dart`

This task builds the input form only — matching the confirmed screenshot (design spec §8): header, ticket/price fields with quick-select chips, platform/cinema dropdowns, live total, and the "OPTIMIZE DEALS" button. Task 11 adds the results panels.

- [ ] **Step 1: Write the screen**

```dart
// lib/features/benefits/movie_deals/screens/movie_deals_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_ticket_request.dart';
import '../providers/movie_deals_provider.dart';
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

  static const _platforms = ['BookMyShow', 'PVR', 'INOX', 'Cinepolis', 'Moviemax'];
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
          style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
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
                    style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
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
                    style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
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

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/benefits/movie_deals/screens/movie_deals_screen.dart`
Expected: One error — `movie_deals_results.dart` doesn't exist yet (created in Task 11). This is expected; do not stub it out here.

- [ ] **Step 3: Commit is deferred to Task 11**

This file references `MovieDealsResults`, which doesn't exist until Task 11 — committing now would leave the worktree in a non-compiling state. Proceed directly to Task 11; both files commit together there.

---

## Task 11: Results panels — Best Card You Own / Best Card Overall

**Files:**
- Create: `lib/features/benefits/movie_deals/screens/movie_deals_results.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_results_test.dart`

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

MovieDealCandidate _candidate({required String cardId, required bool isOwned, required double savings}) {
  final rule = MovieDealRule(
    benefitId: 'b-$cardId',
    catalogCardId: cardId,
    title: 'Test rule',
    offerType: MovieDealOfferType.percentDiscount,
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
    usageConfidence: MovieDealUsageConfidence.unverified,
    platformConfidence: MovieDealPlatformConfidence.explicit,
    explanation: 'saves ₹$savings',
  );
}

void main() {
  const request = MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300);

  testWidgets('renders distinct owned and overall panels when winners differ', (tester) async {
    final owned = _candidate(cardId: 'owned', isOwned: true, savings: 100);
    final overall = _candidate(cardId: 'unowned', isOwned: false, savings: 300);
    final recommendation = MovieDealsRecommendation(
      candidates: [overall, owned],
      rejectedCandidates: const [],
      bestOwned: owned,
      bestOverall: overall,
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

  testWidgets('shows "Also best overall" label when the same card wins both pools', (tester) async {
    final winner = _candidate(cardId: 'shared', isOwned: true, savings: 300);
    final recommendation = MovieDealsRecommendation(
      candidates: [winner],
      rejectedCandidates: const [],
      bestOwned: winner,
      bestOverall: winner,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(home: Scaffold(body: MovieDealsResults(request: request))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('BEST CARD YOU OWN'), findsOneWidget);
    expect(find.textContaining('Also best overall'), findsOneWidget);
    // Only ONE card tile should render, not a duplicate.
    expect(find.textContaining('Card shared'), findsOneWidget);
  });

  testWidgets('shows a no-deal message when neither pool has a winner', (tester) async {
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
import '../../../../core/theme/app_theme.dart';
import '../domain/movie_deal_candidate.dart';
import '../domain/movie_ticket_request.dart';
import '../providers/movie_deals_provider.dart';

/// Design spec §8 — two independent panels, ranked separately. Ownership is
/// never a scoring bonus (this is enforced by movie_deal_evaluator.dart;
/// this widget only renders whatever bestOwned/bestOverall it's given).
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
      error: (error, stack) => _buildRetryCard(context, ref, error.toString()),
    );
  }

  Widget _buildRecommendation(
      BuildContext context, WidgetRef ref, MovieDealsRecommendation recommendation) {
    if (recommendation.status == MovieDealsStatus.unavailable) {
      return _buildRetryCard(context, ref, 'Movie deals data is unavailable right now.');
    }

    final owned = recommendation.bestOwned;
    final overall = recommendation.bestOverall;
    final sharedWinner = owned != null && overall != null && owned.cardId == overall.cardId && owned.benefitId == overall.benefitId;

    if (owned == null && overall == null) {
      return _buildNoDealCard(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (owned != null)
          _CandidatePanel(
            heading: 'BEST CARD YOU OWN',
            candidate: owned,
            trailingLabel: sharedWinner ? 'Also best overall' : null,
          ),
        if (owned != null && !sharedWinner) const SizedBox(height: 16),
        if (overall != null && !sharedWinner)
          _CandidatePanel(heading: 'BEST CARD OVERALL', candidate: overall, isOwned: false),
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
        style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildRetryCard(BuildContext context, WidgetRef ref, String message) {
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
            style: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
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

class _CandidatePanel extends StatelessWidget {
  const _CandidatePanel({
    required this.heading,
    required this.candidate,
    this.isOwned,
    this.trailingLabel,
  });

  final String heading;
  final MovieDealCandidate candidate;
  final bool? isOwned;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final owned = isOwned ?? candidate.isOwned;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(
          color: owned ? AppColors.neonCyan.withValues(alpha: 0.25) : AppColors.violet.withValues(alpha: 0.25),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 11, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            candidate.rule.cardName ?? candidate.title,
            style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
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
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
          Text(
            candidate.explanation,
            style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${candidate.grossAmount.toStringAsFixed(0)} → ₹${candidate.finalAmount.toStringAsFixed(0)} · Save ₹${candidate.savings.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.neonCyan, fontSize: 13),
          ),
          if (trailingLabel != null) ...[
            const SizedBox(height: 8),
            Text(trailingLabel!, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_results_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Verify the screen from Task 10 now compiles**

Run: `flutter analyze lib/features/benefits/movie_deals/`
Expected: No errors.

- [ ] **Step 6: Commit both Task 10 and Task 11 files together**

```bash
git add lib/features/benefits/movie_deals/screens/movie_deals_screen.dart lib/features/benefits/movie_deals/screens/movie_deals_results.dart test/features/benefits/movie_deals/movie_deals_results_test.dart
git commit -m "feat: add Movie Deals screen with independent owned/overall result panels"
```

---

## Task 12: Crowd-source confirmation write path

**Files:**
- Modify: `lib/core/repositories/movie_deals_repository.dart` (add `insertConfirmation` to `MovieDealsDataSource`, `SupabaseMovieDealsDataSource`)
- Modify: `lib/features/benefits/movie_deals/screens/movie_deals_results.dart`
- Test: `test/features/benefits/movie_deals/movie_deals_repository_test.dart` (append)

Design spec §6/§8 describes a "Did this work at {platform}?" prompt after a user acts on a flagged (`communityConfirmed` or `unconfirmed`) recommendation. Tasks 7–8 built the read side (aggregating existing confirmations into `platformConfidence`); this task adds the write side that actually populates the table.

- [ ] **Step 1: Add the failing repository test**

Append to `test/features/benefits/movie_deals/movie_deals_repository_test.dart`, inside the existing `group('MovieDealsSupabaseRepository', ...)`:

```dart
    test('confirmPlatform delegates to the data source with the given ids', () async {
      final calls = <(String, String, String)>[];
      final dataSource = _FakeDataSource();
      final repository = MovieDealsSupabaseRepository(dataSource);

      // _FakeDataSource.insertConfirmation is added in Step 2 below — this
      // test exercises the repository's pass-through, not the fake's own
      // storage (the fake just records the call for assertion).
      await repository.confirmPlatform(
        benefitId: 'b1',
        platform: 'PVR',
        userId: 'user1',
      );

      expect(dataSource.confirmationCalls, hasLength(1));
      expect(dataSource.confirmationCalls.first, ('b1', 'PVR', 'user1'));
    });
```

Also add `confirmationCalls` tracking and the `insertConfirmation` override to `_FakeDataSource` in the same file:

```dart
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

  // ... existing overrides unchanged ...

  @override
  Future<void> insertConfirmation({
    required String benefitId,
    required String platform,
    required String userId,
  }) async {
    confirmationCalls.add((benefitId, platform, userId));
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: FAIL — compile error, `MovieDealsDataSource.insertConfirmation` and `MovieDealsRepository.confirmPlatform` don't exist yet.

- [ ] **Step 3: Add the write methods to the repository**

In `lib/core/repositories/movie_deals_repository.dart`, add `confirmPlatform` to the `MovieDealsRepository` interface:

```dart
abstract interface class MovieDealsRepository {
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  );

  /// Records a user's report that [benefitId] worked at [platform]. Design
  /// spec §6 — write-only, immutable; no update/delete from the client.
  Future<void> confirmPlatform({
    required String benefitId,
    required String platform,
    required String userId,
  });
}
```

Add `insertConfirmation` to the `MovieDealsDataSource` interface:

```dart
abstract interface class MovieDealsDataSource {
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
```

Add the implementation to `MovieDealsSupabaseRepository`:

```dart
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
```

Add the implementation to `SupabaseMovieDealsDataSource`:

```dart
  @override
  Future<void> insertConfirmation({
    required String benefitId,
    required String platform,
    required String userId,
  }) async {
    await _client.from('benefit_platform_confirmations').insert({
      'benefit_id': benefitId,
      'platform': platform,
      'user_id': userId,
    });
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_repository_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Add the confirmation prompt to the results panel**

In `lib/features/benefits/movie_deals/screens/movie_deals_results.dart`, add the prompt as a dismissible banner shown under any panel whose candidate has `platformConfidence != explicit` and the search had a `preferredPlatform` set. Modify `_CandidatePanel` to accept an optional confirmation callback and modify `MovieDealsResults._buildRecommendation` to wire it:

```dart
class _CandidatePanel extends StatefulWidget {
  const _CandidatePanel({
    required this.heading,
    required this.candidate,
    this.isOwned,
    this.trailingLabel,
    this.onConfirmPlatform,
  });

  final String heading;
  final MovieDealCandidate candidate;
  final bool? isOwned;
  final String? trailingLabel;

  /// Called with the searched platform when the user confirms this deal
  /// worked there. Null when there's nothing to confirm (explicit match,
  /// or an "any platform" search).
  final Future<void> Function(String platform)? onConfirmPlatform;

  @override
  State<_CandidatePanel> createState() => _CandidatePanelState();
}

class _CandidatePanelState extends State<_CandidatePanel> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final owned = widget.isOwned ?? candidate.isOwned;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border.all(
          color: owned ? AppColors.neonCyan.withValues(alpha: 0.25) : AppColors.violet.withValues(alpha: 0.25),
          width: 1.2,
        ),
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
                  style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
          Text(
            candidate.explanation,
            style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            '₹${candidate.grossAmount.toStringAsFixed(0)} → ₹${candidate.finalAmount.toStringAsFixed(0)} · Save ₹${candidate.savings.toStringAsFixed(0)}',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: AppColors.neonCyan, fontSize: 13),
          ),
          if (widget.trailingLabel != null) ...[
            const SizedBox(height: 8),
            Text(widget.trailingLabel!, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic)),
          ],
          if (widget.onConfirmPlatform != null && !_confirmed) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                await widget.onConfirmPlatform!(candidate.rule.platform ?? '');
                if (mounted) setState(() => _confirmed = true);
              },
              child: const Text('Did this work here? Let us know'),
            ),
          ],
          if (_confirmed) ...[
            const SizedBox(height: 12),
            Text('Thanks — this helps other users.', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.neonCyan)),
          ],
        ],
      ),
    );
  }
}
```

Update `MovieDealsResults._buildRecommendation` to pass `onConfirmPlatform` when `request.preferredPlatform` is set and the candidate's `platformConfidence` isn't already `explicit`:

```dart
  Widget _buildRecommendation(
      BuildContext context, WidgetRef ref, MovieDealsRecommendation recommendation) {
    if (recommendation.status == MovieDealsStatus.unavailable) {
      return _buildRetryCard(context, ref, 'Movie deals data is unavailable right now.');
    }

    final owned = recommendation.bestOwned;
    final overall = recommendation.bestOverall;
    final sharedWinner = owned != null && overall != null && owned.cardId == overall.cardId && owned.benefitId == overall.benefitId;

    if (owned == null && overall == null) {
      return _buildNoDealCard(context);
    }

    Future<void> Function(String)? confirmCallbackFor(MovieDealCandidate candidate) {
      if (request.preferredPlatform == null) return null;
      if (candidate.platformConfidence == MovieDealPlatformConfidence.explicit) return null;
      return (platform) => ref.read(movieDealsRepositoryProvider).confirmPlatform(
            benefitId: candidate.benefitId,
            platform: request.preferredPlatform!,
            userId: ref.read(currentUserProvider)!.id,
          );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (owned != null)
          _CandidatePanel(
            heading: 'BEST CARD YOU OWN',
            candidate: owned,
            trailingLabel: sharedWinner ? 'Also best overall' : null,
            onConfirmPlatform: confirmCallbackFor(owned),
          ),
        if (owned != null && !sharedWinner) const SizedBox(height: 16),
        if (overall != null && !sharedWinner)
          _CandidatePanel(
            heading: 'BEST CARD OVERALL',
            candidate: overall,
            isOwned: false,
            onConfirmPlatform: confirmCallbackFor(overall),
          ),
      ],
    );
  }
```

Add the two new imports this requires at the top of the file:

```dart
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
```

- [ ] **Step 6: Verify existing widget tests still pass**

Run: `flutter test test/features/benefits/movie_deals/movie_deals_results_test.dart`
Expected: PASS (4 tests) — the confirmation button only renders when `onConfirmPlatform` is non-null, which requires `request.preferredPlatform` to be set; none of the existing tests set it, so this change is additive and shouldn't affect them. If a test fails because `ref.read(currentUserProvider)` throws (no authenticated user in the test's `ProviderScope`), that test's `request` needs `preferredPlatform: null` explicitly confirmed — check before assuming a new bug.

- [ ] **Step 7: Commit**

```bash
git add lib/core/repositories/movie_deals_repository.dart lib/features/benefits/movie_deals/screens/movie_deals_results.dart test/features/benefits/movie_deals/movie_deals_repository_test.dart
git commit -m "feat: add crowd-source platform confirmation write path"
```

---

## Task 13: Wire the 5th navigation tab

**Files:**
- Modify: `lib/core/router/app_router.dart:17,19-24,76-81,129-134,206-211`

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
Expected: All prior tests still PASS (this task adds no new automated test — router tab-index logic has no existing test coverage in this codebase to extend; verify manually per Task 13).

- [ ] **Step 6: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat: add Movie Deals as 5th navigation tab"
```

---

## Task 14: Manual verification in the running app

**Files:**
- No code changes

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, exit code 0.

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: No errors (warnings acceptable only if they pre-date this feature — check `git stash` + re-run if unsure whether a warning is new).

- [ ] **Step 3: Launch the app and navigate to the new tab**

Start the app (web target, matching this worktree's platform):
```bash
flutter run -d chrome --dart-define-from-file=dart_defines.json
```

Log in, then tap/click the new "Movie Deals" tab (5th item, film icon).

- [ ] **Step 4: Verify the input form renders per design spec §8**

Check: header with film icon + "MOVIE TICKET OPTIMIZER" + "AI RULE OPTIMIZATION ENGINE" badge; Tickets/Price fields; quick-select chips (2/3/4/6 tickets, ₹200/250/300/400); Platform/Cinema dropdowns defaulting to "ANY PLATFORM"/"ANY CINEMA"; live total amount bar; "OPTIMIZE DEALS" button disabled until both fields are filled.

- [ ] **Step 5: Verify a real search against live data**

Enter 2 tickets, ₹300 price, leave platform/cinema as "ANY". Tap "OPTIMIZE DEALS". Confirm:
- Either both "BEST CARD YOU OWN" and "BEST CARD OVERALL" panels render (if they differ), or one panel with "Also best overall" (if they're the same card), or a "No verified eligible deal" message.
- No raw exception/error text is shown to the user.
- The savings math shown matches what you'd calculate by hand for whichever card appears (cross-check against the real seed-data row for that card's benefit, per design spec §4.3).

- [ ] **Step 6: Verify a platform-specific search**

Select "BookMyShow" as the platform, submit again. Confirm any card with `platform: null` in its underlying rule (i.e., not tied to a specific platform) shows the "Platform not confirmed for this offer" chip rather than being presented as an unqualified match.

- [ ] **Step 7: Check responsive layout**

Resize the browser window to ~375px wide. Confirm the form fields stack sensibly and the result panels don't overflow horizontally.

- [ ] **Step 8: Report findings**

If any step above fails, this is the final task — do not mark it complete. Return to the relevant task's domain logic or repository query and fix the root cause (per superpowers:systematic-debugging), not just the symptom visible in the UI, then re-run this task's steps from the top.
