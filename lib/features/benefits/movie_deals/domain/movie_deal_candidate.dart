// lib/features/benefits/movie_deals/domain/movie_deal_candidate.dart
import 'movie_deal_rule.dart';

enum MovieDealUsageConfidence { verified, unverified, unavailable }

/// Design spec §5 (with the notRequested correction). Computed per
/// evaluation from eligibleMoviePlatformsFor(rule) (movie_platform_aliases.dart)
/// — NEVER from raw rule.partners — depends on both the rule and the specific
/// platform searched for.
enum MovieDealPlatformConfidence {
  /// eligibleMoviePlatformsFor(rule) is non-empty and contains the searched
  /// platform, OR the search was unconstrained ("Any Platform") and
  /// eligibleMoviePlatformsFor(rule) is non-empty.
  explicit,

  /// eligibleMoviePlatformsFor(rule) is empty, but >=1 confirmed user report
  /// exists for the searched platform (or, under "Any Platform," for ANY
  /// platform on this benefit) — takes precedence over notRequested whenever
  /// a confirmation exists (design spec §5 precedence correction).
  communityConfirmed,

  /// eligibleMoviePlatformsFor(rule) is empty, no confirmations exist, and a
  /// SPECIFIC platform was requested (not "Any Platform").
  unconfirmed,

  /// The search was unconstrained ("Any Platform"), eligibleMoviePlatformsFor(rule)
  /// is empty, AND no confirmations exist for this benefit under any platform.
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
    this.confirmationCount,
  });

  final bool isOwned;
  final MovieDealUsageConfidence usageConfidence;
  final int usedTickets;
  final int usedTransactions;
  final double? milestoneSpend;

  /// Platforms with >=1 confirmation for THIS SPECIFIC benefitId
  /// (design spec §6/§5) — never a card-wide union across benefits.
  final Set<String> confirmedPlatforms;

  /// Distinct-user confirmation count for THIS SPECIFIC benefitId, from
  /// benefit_platform_confirmation_counts.confirmation_count. Null (never a
  /// fabricated 0) when no confirmation row exists for this benefit at all —
  /// distinct from confirmedPlatforms being empty for a different platform
  /// than the one searched.
  final int? confirmationCount;
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
    this.usedTransactions = 0,
    this.milestoneSpend,
    this.confirmationCount,
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

  /// Pass-through of MovieDealContext.usedTransactions — how many
  /// redemptions have already counted against rule.cycleRedemptionLimit
  /// (bogo) this cycle. Meaningless (always 0) when the rule has no
  /// cycleRedemptionLimit to count against.
  final int usedTransactions;

  /// Pass-through of MovieDealContext.milestoneSpend — the prior completed
  /// cycle's category spend, to render against rule.milestoneThreshold. Null
  /// when unavailable, never a fabricated 0.
  final double? milestoneSpend;

  /// Pass-through of MovieDealContext.confirmationCount — distinct-user
  /// count backing a communityConfirmed platformConfidence. Null when no
  /// confirmation row exists for this benefit, never a fabricated 0.
  final int? confirmationCount;
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
///
/// guaranteedOwned/guaranteedOverall/potentialOwned/potentialOverall are the
/// FULL ranked lists per tier×ownership group (each already sorted by
/// evaluateMovieDeals' own comparator) — the UI shows every eligible
/// candidate per group, not just the top pick. The best* singular fields
/// are kept as a derived convenience (each is simply the corresponding
/// list's first entry, or null when empty) for any caller that only wants
/// the single winner.
class MovieDealsRecommendation {
  const MovieDealsRecommendation({
    required this.candidates,
    required this.rejectedCandidates,
    this.status = MovieDealsStatus.available,
    this.bestGuaranteedOwned,
    this.bestGuaranteedOverall,
    this.bestPotentialOwned,
    this.bestPotentialOverall,
    this.guaranteedOwned = const [],
    this.guaranteedOverall = const [],
    this.potentialOwned = const [],
    this.potentialOverall = const [],
  });

  final List<MovieDealCandidate> candidates;
  final List<RejectedMovieDealCandidate> rejectedCandidates;
  final MovieDealsStatus status;
  final MovieDealCandidate? bestGuaranteedOwned;
  final MovieDealCandidate? bestGuaranteedOverall;
  final MovieDealCandidate? bestPotentialOwned;
  final MovieDealCandidate? bestPotentialOverall;
  final List<MovieDealCandidate> guaranteedOwned;
  final List<MovieDealCandidate> guaranteedOverall;
  final List<MovieDealCandidate> potentialOwned;
  final List<MovieDealCandidate> potentialOverall;
}
