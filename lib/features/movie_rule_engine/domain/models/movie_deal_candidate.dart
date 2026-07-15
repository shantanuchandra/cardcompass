import 'movie_deal_rule.dart';

enum MovieDealUsageConfidence { verified, unverified, unavailable }

/// Distinguishes a successfully evaluated empty result from an unavailable
/// data source. Consumers must not present the latter as "no deals".
enum MovieDealsStatus { available, unavailable }

/// Context supplied by the repository for one catalog card. It deliberately
/// contains only already-observed state, keeping the evaluator pure.
class MovieDealContext {
  const MovieDealContext({
    this.isOwned = false,
    this.usageConfidence = MovieDealUsageConfidence.unverified,
    this.usedTickets = 0,
    this.usedTransactions = 0,
    this.milestoneSpend,
  });

  final bool isOwned;
  final MovieDealUsageConfidence usageConfidence;
  final int usedTickets;
  final int usedTransactions;
  final double? milestoneSpend;
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
  MovieDealsRecommendation({
    required List<MovieDealCandidate> candidates,
    required List<RejectedMovieDealCandidate> rejectedCandidates,
    this.status = MovieDealsStatus.available,
    this.bestOwned,
    this.bestOverall,
  })  : candidates = List.unmodifiable(candidates),
        rejectedCandidates = List.unmodifiable(rejectedCandidates);

  final List<MovieDealCandidate> candidates;
  final List<RejectedMovieDealCandidate> rejectedCandidates;
  final MovieDealsStatus status;
  final MovieDealCandidate? bestOwned;
  final MovieDealCandidate? bestOverall;
}
