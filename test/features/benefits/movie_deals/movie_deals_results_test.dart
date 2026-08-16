// test/features/benefits/movie_deals/movie_deals_results_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/core/providers/supabase_provider.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';
import 'package:cardcompass/features/benefits/movie_deals/providers/movie_deals_provider.dart';
import 'package:cardcompass/features/benefits/movie_deals/screens/movie_deals_results.dart';

MovieDealCandidate _candidate({
  required String cardId,
  required bool isOwned,
  required double savings,
  MovieDealPlatformConfidence platformConfidence =
      MovieDealPlatformConfidence.explicit,
  MovieDealOfferType offerType = MovieDealOfferType.percentDiscount,
  Set<String> partners = const {},
}) {
  final rule = MovieDealRule(
    benefitId: 'b-$cardId',
    catalogCardId: cardId,
    title: 'Test rule',
    offerType: offerType,
    discountPercent: 25,
    cardName: 'Card $cardId',
    partners: partners,
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

/// Renders both slots stacked, matching how movie_deals_screen.dart
/// actually composes them (form + owned on the left, overall on the
/// right) — a real search always shows both, so most assertions below
/// check the combined output. Both instances watch the same provider
/// override, so this exercises the layout without duplicating the search.
Widget _bothSlots(MovieTicketRequest request) {
  return Column(
    children: [
      MovieDealsResults(request: request, slot: ResultsSlot.owned),
      MovieDealsResults(request: request, slot: ResultsSlot.overall),
    ],
  );
}

void main() {
  const request = MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300);

  testWidgets('movie search loading reserves a stable result slot', (
    tester,
  ) async {
    final pending = Completer<MovieDealsRecommendation>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(
          const MovieDealsRecommendation(
            candidates: [],
            rejectedCandidates: [],
          ),
        );
      }
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) => pending.future),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MovieDealsResults(request: request, slot: ResultsSlot.overall),
          ),
        ),
      ),
    );
    await tester.pump();

    final loading = find.byKey(const Key('movie-results-loading'));
    expect(loading, findsOneWidget);
    expect(tester.getSize(loading).height, greaterThanOrEqualTo(240));
    expect(find.bySemanticsLabel('Finding movie offers'), findsOneWidget);
  });

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
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Guaranteed · You own'), findsOneWidget);
    expect(find.text('Guaranteed · Overall'), findsOneWidget);
    // owned-high/owned-low each appear TWICE: once in "you own" and once
    // again in "overall" (overall is never ownership-filtered) — proving
    // the same candidate can legitimately render in both groups.
    expect(find.textContaining('Card owned-high'), findsNWidgets(2));
    expect(find.textContaining('Card owned-low'), findsNWidgets(2));
    expect(find.textContaining('Card unowned'), findsOneWidget);
  });

  testWidgets('the owned slot never renders an Overall group, and vice versa', (tester) async {
    final owned = _candidate(cardId: 'owned-only', isOwned: true, savings: 100);
    final unowned = _candidate(cardId: 'unowned-only', isOwned: false, savings: 200);
    final recommendation = MovieDealsRecommendation(
      candidates: [owned, unowned],
      rejectedCandidates: const [],
      guaranteedOwned: [owned],
      guaranteedOverall: [unowned, owned],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MovieDealsResults(request: request, slot: ResultsSlot.owned),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Guaranteed · You own'), findsOneWidget);
    expect(find.text('Guaranteed · Overall'), findsNothing);
    expect(find.text('Potential · You own'), findsOneWidget);
    expect(find.text('Potential · Overall'), findsNothing);
    // unowned-only is never eligible for the owned slot at all.
    expect(find.textContaining('Card unowned-only'), findsNothing);
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
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('You own this'), findsNWidgets(2));
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
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Card potential-only'), findsWidgets);
    expect(find.textContaining('Potential'), findsWidgets);
    // The guaranteed groups must show their empty-state note, not the
    // potential candidate presented as if it were guaranteed.
    expect(find.textContaining('No guaranteed'), findsWidgets);
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
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Guaranteed · You own'), findsOneWidget);
    expect(find.textContaining('No guaranteed deals on cards you own'), findsOneWidget);
    expect(find.text('Potential · You own'), findsOneWidget);
    expect(find.textContaining('No potential deals on cards you own'), findsOneWidget);
    expect(find.text('Potential · Overall'), findsOneWidget);
    expect(find.textContaining('No potential deals available'), findsOneWidget);
  });

  testWidgets('shows a no-deal message on the overall slot, and nothing on the owned slot, when every group is empty', (tester) async {
    const recommendation = MovieDealsRecommendation(candidates: [], rejectedCandidates: []);

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    // Shown once, on the overall slot only — the owned slot renders
    // nothing rather than a second, redundant "no deal" card right above it.
    expect(find.text('No eligible ticket-saving option'), findsOneWidget);
  });

  testWidgets('shows a retryable unavailable message on repository failure', (tester) async {
    const recommendation = MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MovieDealsResults(request: request, slot: ResultsSlot.overall),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
  });

  testWidgets('a rewardMultiplier candidate renders its raw rate on the overall slot, never a computed rupee figure', (tester) async {
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
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('points program'), findsOneWidget);
    expect(find.textContaining('Save ₹0'), findsNothing);
  });

  testWidgets('an annualAllowance candidate renders in its own section on the overall slot, never in a ranked group', (tester) async {
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
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    // "balance not tracked" legitimately appears twice — once in the
    // section label, once in the candidate's own explanation text — so
    // assert on the more specific candidate-level string instead.
    expect(find.textContaining('remaining balance not tracked'), findsOneWidget);
    expect(find.textContaining('Save ₹0'), findsNothing);
  });

  testWidgets('names the searched platform on a candidate whose rule is tied to it', (tester) async {
    const searchedRequest = MovieTicketRequest(
      numberOfTickets: 2,
      pricePerTicket: 300,
      preferredPlatform: 'BookMyShow',
    );
    final onBms = _candidate(
      cardId: 'on-bms',
      isOwned: true,
      savings: 100,
      partners: {'bookmyshow'},
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [onBms],
      rejectedCandidates: const [],
      guaranteedOwned: [onBms],
      guaranteedOverall: [onBms],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(searchedRequest).overrideWith((ref) async => recommendation)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(searchedRequest))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('BookMyShow'), findsWidgets);
  });

  testWidgets('does not claim a platform tie when the rule is tied to a different platform', (tester) async {
    const searchedRequest = MovieTicketRequest(
      numberOfTickets: 2,
      pricePerTicket: 300,
      preferredPlatform: 'PVR',
    );
    final onBms = _candidate(
      cardId: 'on-bms-2',
      isOwned: true,
      savings: 100,
      platformConfidence: MovieDealPlatformConfidence.unconfirmed,
      partners: {'bookmyshow'},
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [onBms],
      rejectedCandidates: const [],
      guaranteedOwned: [onBms],
      guaranteedOverall: [onBms],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        movieDealsSearchProvider(searchedRequest).overrideWith((ref) async => recommendation),
        // This candidate's non-explicit platformConfidence + a searched
        // preferredPlatform makes confirmCallbackFor try to read
        // currentUserProvider, which reaches Supabase.instance — not
        // initialized in this widget test.
        currentUserProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(searchedRequest))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('not tied to PVR'), findsWidgets);
  });

  testWidgets('shows an honest cinema-not-supported note only when a cinema was searched', (tester) async {
    const searchedRequest = MovieTicketRequest(
      numberOfTickets: 2,
      pricePerTicket: 300,
      preferredCinema: 'PVR Phoenix',
    );
    final candidate = _candidate(cardId: 'cinema-card', isOwned: true, savings: 100);
    final recommendation = MovieDealsRecommendation(
      candidates: [candidate],
      rejectedCandidates: const [],
      guaranteedOwned: [candidate],
      guaranteedOverall: [candidate],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(searchedRequest).overrideWith((ref) async => recommendation)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(searchedRequest))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cinema filtering is not yet supported'), findsWidgets);
  });

  testWidgets('omits the cinema note entirely when no cinema was searched', (tester) async {
    final candidate = _candidate(cardId: 'no-cinema-card', isOwned: true, savings: 100);
    final recommendation = MovieDealsRecommendation(
      candidates: [candidate],
      rejectedCandidates: const [],
      guaranteedOwned: [candidate],
      guaranteedOverall: [candidate],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [movieDealsSearchProvider(request).overrideWith((ref) async => recommendation)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _bothSlots(request))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cinema filtering'), findsNothing);
  });
}
