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
