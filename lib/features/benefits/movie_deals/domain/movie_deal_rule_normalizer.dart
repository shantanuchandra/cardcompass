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
  // ONLY for the dispatch comparisons (`unit != 'fixed'`, `unit == 'fixed'`).
  final rawUnit = _string(config['unit']);
  final unit = rawUnit?.toLowerCase();
  final threshold = _number(config['threshold_amount']);
  final milestoneType = _string(config['milestone_type']);
  if (milestoneType != null || threshold != null) {
    return _normalizeMilestone(source);
  }

  final category = _string(config['category'])?.toLowerCase() ?? '';
  final mentionsMovies = category
      .split(',')
      .map((c) => c.trim())
      .contains('movies');
  final rate = _number(config['multiplier']) ?? _number(config['base_rate']);
  if (mentionsMovies && rate != null && rawUnit != null && unit != 'fixed') {
    return _normalizeRewardMultiplier(source, rawUnit, rate, category);
  }

  if (unit == 'fixed') {
    final amount =
        _number(config['annual_cap']) ??
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
  if (discountPercent == null ||
      discountPercent <= 0 ||
      discountPercent > 100) {
    return const RejectedMovieDealRule(
      'A percentage offer requires a rate between 0 and 100.',
    );
  }
  // max_discount_per_transaction already exists on real, live percent-type
  // rows (e.g. "10% Off on Tira Orders", "Fuel Surcharge Waiver") — this key
  // was previously only ever read for bogo, silently dropping the cap for
  // every capped percentDiscount row. Optional: absent means genuinely
  // uncapped, never defaulted to 0 (design spec §4.2's "never invented"
  // convention).
  final perTransactionCap = _number(
    source.valueConfig['max_discount_per_transaction'],
  );
  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      bankName: source.bankName,
      displayPriority: source.displayPriority,
      validityStart: source.validityStart,
      validityEnd: source.validityEnd,
      offerType: MovieDealOfferType.percentDiscount,
      partners: source.partners,
      discountPercent: discountPercent,
      perTransactionCap: perTransactionCap,
    ),
  );
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
  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      bankName: source.bankName,
      displayPriority: source.displayPriority,
      validityStart: source.validityStart,
      validityEnd: source.validityEnd,
      offerType: MovieDealOfferType.fixedDiscount,
      partners: source.partners,
      fixedAmount: discountAmount,
      cycleAmountCap: cycleCap,
    ),
  );
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
  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      bankName: source.bankName,
      displayPriority: source.displayPriority,
      validityStart: source.validityStart,
      validityEnd: source.validityEnd,
      offerType: MovieDealOfferType.bogo,
      partners: source.partners,
      buyCount: 1,
      freeCount: 1,
      perTransactionCap: perTxnCap,
      cycleRedemptionLimit: cycleLimit,
    ),
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
  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      bankName: source.bankName,
      displayPriority: source.displayPriority,
      validityStart: source.validityStart,
      validityEnd: source.validityEnd,
      offerType: MovieDealOfferType.annualAllowance,
      partners: source.partners,
      annualCap: annualCap,
    ),
  );
}

RuleNormalizationResult _normalizeMilestone(MovieBenefitSource source) {
  final threshold = _number(source.valueConfig['threshold_amount']);
  final reward = _number(source.valueConfig['reward_value']);
  if (threshold == null || reward == null) {
    return const RejectedMovieDealRule(
      'A milestone requires both a threshold and reward.',
    );
  }
  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      bankName: source.bankName,
      displayPriority: source.displayPriority,
      validityStart: source.validityStart,
      validityEnd: source.validityEnd,
      offerType: MovieDealOfferType.milestone,
      partners: source.partners,
      milestoneThreshold: threshold,
      milestoneReward: reward,
    ),
  );
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
  return AcceptedMovieDealRule(
    MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      bankName: source.bankName,
      displayPriority: source.displayPriority,
      validityStart: source.validityStart,
      validityEnd: source.validityEnd,
      offerType: MovieDealOfferType.rewardMultiplier,
      partners: source.partners,
      rewardMultiplierRate: rate,
      rewardMultiplierUnit: unit,
      qualifyingCategories: categories,
      excludedCategories: source.excludedCategories,
    ),
  );
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
