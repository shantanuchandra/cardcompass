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
