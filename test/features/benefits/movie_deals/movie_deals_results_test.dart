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

  testWidgets('lists every candidate in each ranked group, not just one winner', (tester) async {
    final ownedHigh = _candidate(cardId: 'owned-high', isOwned: true, savings: 150);
    final ownedLow = _candidate(cardId: 'owned-low', isOwned: true, savings: 50);
    final unowned = _candidate(cardId: 'unowned', isOwned: false, savings: 300);
    final recommendation = MovieDealsRecommendation(
      candidates: [ownedHigh, ownedLow, unowned],
      rejectedCandidates: const [],
      guaranteedOwned: [ownedHigh, ownedLow],
      guaranteedOverall: [unowned, ownedHigh, ownedLow],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('GUARANTEED · YOU OWN'), findsOneWidget);
    expect(find.text('GUARANTEED · OVERALL'), findsOneWidget);
    // owned-high/owned-low each appear TWICE: once in "you own" and once
    // again in "overall" (overall is never ownership-filtered) — proving
    // the same candidate can legitimately render in both groups.
    expect(find.textContaining('Card owned-high'), findsNWidgets(2));
    expect(find.textContaining('Card owned-low'), findsNWidgets(2));
    expect(find.textContaining('Card unowned'), findsOneWidget);
  });

  testWidgets('shows an ownership badge on a candidate that is owned', (tester) async {
    final owned = _candidate(cardId: 'owned', isOwned: true, savings: 100);
    final recommendation = MovieDealsRecommendation(
      candidates: [owned],
      rejectedCandidates: const [],
      guaranteedOwned: [owned],
      guaranteedOverall: [owned],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('YOU OWN THIS'), findsNWidgets(2));
  });

  testWidgets('falls back to potential groups when no guaranteed candidate exists', (tester) async {
    final potential = _candidate(
      cardId: 'potential-only',
      isOwned: true,
      savings: 6000,
      platformConfidence: MovieDealPlatformConfidence.notRequested,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [potential],
      rejectedCandidates: const [],
      potentialOwned: [potential],
      potentialOverall: [potential],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Card potential-only'), findsWidgets);
    expect(find.textContaining('Potential — remaining balance not verified'), findsWidgets);
    // The guaranteed groups must show their empty-state note, not the
    // potential candidate presented as if it were guaranteed.
    expect(find.textContaining('No guaranteed deals'), findsWidgets);
  });

  testWidgets('shows an empty-state note for a group with zero eligible candidates, never hides the header', (tester) async {
    final overallOnly = _candidate(cardId: 'overall-only', isOwned: false, savings: 100);
    final recommendation = MovieDealsRecommendation(
      candidates: [overallOnly],
      rejectedCandidates: const [],
      guaranteedOverall: [overallOnly],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('GUARANTEED · YOU OWN'), findsOneWidget);
    expect(find.textContaining('No guaranteed deals on cards you own'), findsOneWidget);
    expect(find.text('POTENTIAL · YOU OWN'), findsOneWidget);
    expect(find.textContaining('No potential deals on cards you own'), findsOneWidget);
    expect(find.text('POTENTIAL · OVERALL'), findsOneWidget);
    expect(find.textContaining('No potential deals available'), findsOneWidget);
  });

  testWidgets('shows a no-deal message when every group and every dedicated section is empty', (tester) async {
    const recommendation = MovieDealsRecommendation(candidates: [], rejectedCandidates: []);

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
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
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
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
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('points program'), findsOneWidget);
    expect(find.textContaining('Save ₹0'), findsNothing);
  });

  testWidgets('an annualAllowance candidate renders in its own section, never in a ranked group', (tester) async {
    final annualRule = MovieDealRule(
      benefitId: 'b-annual-card',
      catalogCardId: 'annual-card',
      title: 'SBI Card ELITE Free Movie Tickets',
      cardName: 'SBI Card ELITE',
      offerType: MovieDealOfferType.annualAllowance,
      annualCap: 6000,
    );
    final annualCandidate = MovieDealCandidate(
      cardId: 'annual-card',
      benefitId: 'b-annual-card',
      title: annualRule.title,
      rule: annualRule,
      isOwned: true,
      grossAmount: 600,
      savings: 0,
      finalAmount: 600,
      usageConfidence: MovieDealUsageConfidence.unverified,
      platformConfidence: MovieDealPlatformConfidence.notRequested,
      explanation: 'Up to ₹6000/year in movie tickets — remaining balance not tracked.',
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [annualCandidate],
      rejectedCandidates: const [],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MovieDealsResults(request: request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('balance not tracked'), findsOneWidget);
    expect(find.textContaining('Save ₹0'), findsNothing);
  });
}
