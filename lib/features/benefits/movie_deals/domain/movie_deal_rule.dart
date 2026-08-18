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
    this.bankName,
    this.displayPriority = 0,
    this.validityStart,
    this.validityEnd,
  }) : valueConfig = Map.unmodifiable(valueConfig),
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
  final String? bankName;
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
    this.bankName,
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
  }) : partners = Set.unmodifiable(partners),
       qualifyingCategories = Set.unmodifiable(qualifyingCategories),
       excludedCategories = Set.unmodifiable(excludedCategories);

  final String benefitId;
  final String catalogCardId;
  final String title;
  final String? sourceUrl;
  final String? cardName;
  final String? bankName;
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

  /// Caps a SINGLE booking's discount (e.g. bogo's per-pair cap, or
  /// percentDiscount's per-transaction ceiling — both from
  /// `max_discount_per_transaction`). Distinct from [cycleAmountCap], which
  /// caps a TOTAL across the whole cycle rather than one transaction.
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
