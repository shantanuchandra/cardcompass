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
  required Map<(String, String), MovieDealContext> contexts,
  required DateTime now,
}) {
  final candidates = <MovieDealCandidate>[];
  final rejected = <RejectedMovieDealCandidate>[];

  for (final rule in rules) {
    final context = contexts[(rule.catalogCardId, rule.benefitId)] ?? const MovieDealContext();
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
      usedTransactions: context.usedTransactions,
      milestoneSpend: context.milestoneSpend,
      confirmationCount: context.confirmationCount,
    ));
  }

  // rewardMultiplier and annualAllowance both always report savings=0 (no
  // ₹ figure is invented for either — see _calculateSavings) and are shown
  // in their own dedicated, non-competitive UI section rather than a
  // guaranteed/potential winner slot. Relying on savings=0 alone to lose
  // every ranking comparison was NOT sufficient: as the sole candidate in
  // `candidates`, either type could still become a best* winner by default
  // (no competing candidate to lose to) — excluded here explicitly so a
  // best* field can never surface either type as if it won a comparison,
  // while both remain fully present in `candidates` for their own section.
  final winnerEligible = candidates.where((c) =>
      c.rule.offerType != MovieDealOfferType.rewardMultiplier &&
      c.rule.offerType != MovieDealOfferType.annualAllowance);
  final guaranteed = winnerEligible.where(_isGuaranteed).toList()..sort(_compareCandidates);
  final potential = winnerEligible.where((c) => !_isGuaranteed(c)).toList()..sort(_compareCandidates);

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
///
/// hasNoCapToVerify covers every offer type that has no usage cap to verify
/// against at all, not just the two currently-observed real cases: the one
/// real fixedDiscount row happens to carry a cycleAmountCap (monthly_cap),
/// but the normalizer never requires one (movie_deal_rule_normalizer.dart's
/// _normalizeFixed leaves cycleAmountCap null when monthly_cap is absent
/// from the source row), so a future capless fixedDiscount row must reach
/// this branch too — there being nothing to verify usage against is the
/// actual condition, not "is this the one row we've seen so far."
bool _isGuaranteed(MovieDealCandidate candidate) {
  final hasNoCapToVerify = (candidate.rule.offerType == MovieDealOfferType.percentDiscount) ||
      (candidate.rule.offerType == MovieDealOfferType.bogo &&
          candidate.rule.cycleRedemptionLimit == null) ||
      (candidate.rule.offerType == MovieDealOfferType.fixedDiscount &&
          candidate.rule.cycleAmountCap == null);
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
  // NOTE: a requested platform that doesn't match eligibleMoviePlatformsFor(rule)
  // is deliberately NOT an eligibility cutoff here — it only ever degrades
  // platformConfidence (see _platformConfidence below). Design spec §5's own
  // MovieDealPlatformConfidence doc comments (Task 6) model a platform
  // mismatch as a confidence distinction (explicit vs. communityConfirmed vs.
  // unconfirmed), never as a reason to drop the candidate entirely — the
  // user should still see "this benefit exists, but its platform-match with
  // what you searched for is unconfirmed," not have it disappear outright.

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
      // annualCap is a whole-year budget, not this transaction's discount —
      // there is no remaining-balance tracking anywhere in the schema
      // (MovieDealCandidate.remainingVerifiedUsage is declared but never
      // populated), so how much of it is left for THIS purchase is
      // unknowable. Reporting the raw cap here previously let a ₹6,000
      // annual allowance out-rank a real, computable ₹50 percentDiscount for
      // a ₹500 search — the same category error rewardMultiplier already
      // avoids by reporting 0 instead of inventing a rupee figure.
      savings = 0;
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

// Enumerates all 6 offer types explicitly (no `_` catch-all) so a future
// 7th offer type fails to compile here, the same way it already fails to
// compile in _calculateSavings above — a generic explanation string is a
// deliberate choice for percentDiscount/fixedDiscount/milestone, not a
// fallback for types nobody has decided the wording for.
String _explanation(MovieDealRule rule, double savings,
        MovieDealUsageConfidence confidence) =>
    switch (rule.offerType) {
      MovieDealOfferType.rewardMultiplier =>
        '${rule.rewardMultiplierRate} ${rule.rewardMultiplierUnit} (points program, not a direct discount).',
      MovieDealOfferType.bogo =>
        'BOGO — up to ₹${rule.perTransactionCap?.toStringAsFixed(0)} off, '
            '${rule.cycleRedemptionLimit} redemptions/month.',
      // States the real, unconditional term (the annual cap) rather than a
      // computed ₹ figure for this specific purchase — how much of the
      // ₹X/year budget remains is unknowable (see _calculateSavings), so
      // this must never read like a guaranteed discount on THIS transaction.
      MovieDealOfferType.annualAllowance =>
        'Up to ₹${rule.annualCap?.toStringAsFixed(0)}/year in movie tickets — remaining balance not tracked.',
      MovieDealOfferType.percentDiscount ||
      MovieDealOfferType.fixedDiscount ||
      MovieDealOfferType.milestone =>
        '${rule.offerType.name} saves ₹${savings.toStringAsFixed(2)} (${confidence.name} usage).',
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
