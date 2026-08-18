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
  String? bankName,
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
    bankName: bankName,
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

/// Wraps in a Scaffold + wide SizedBox so the bento grid's LayoutBuilder
/// always resolves to its 3-column desktop arrangement — most assertions
/// below don't care about column count, only that a group's own tile
/// shows the right content, so a stable, roomy width keeps them simple.
Widget _wideHarness(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 1200, child: SingleChildScrollView(child: child)),
    ),
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
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pump();

    final loading = find.byKey(const Key('movie-results-loading'));
    expect(loading, findsOneWidget);
    expect(tester.getSize(loading).height, greaterThanOrEqualTo(240));
    expect(find.bySemanticsLabel('Finding movie offers'), findsOneWidget);
  });

  testWidgets('shows one best match and deduplicates remaining card options', (
    tester,
  ) async {
    final ownedHigh = _candidate(
      cardId: 'owned-high',
      isOwned: true,
      savings: 150,
    );
    final ownedLow = _candidate(
      cardId: 'owned-low',
      isOwned: true,
      savings: 50,
    );
    final unowned = _candidate(cardId: 'unowned', isOwned: false, savings: 300);
    final recommendation = MovieDealsRecommendation(
      candidates: [ownedHigh, ownedLow, unowned],
      rejectedCandidates: const [],
      guaranteedOwned: [ownedHigh, ownedLow],
      guaranteedOverall: [unowned, ownedHigh, ownedLow],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('movie-best-match')), findsOneWidget);
    expect(find.text('Best match'), findsOneWidget);
    expect(find.text('Other cards to consider'), findsOneWidget);
    expect(find.textContaining('Card owned-high'), findsOneWidget);
    expect(find.textContaining('Card owned-low'), findsOneWidget);
    expect(find.textContaining('Card unowned'), findsOneWidget);
  });

  testWidgets('best-match priority favors a guaranteed owned card', (
    tester,
  ) async {
    final owned = _candidate(cardId: 'owned-only', isOwned: true, savings: 100);
    final unowned = _candidate(
      cardId: 'unowned-only',
      isOwned: false,
      savings: 200,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [owned, unowned],
      rejectedCandidates: const [],
      guaranteedOwned: [owned],
      guaranteedOverall: [unowned],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    final bestMatch = find.byKey(const Key('movie-best-match'));
    expect(
      find.descendant(
        of: bestMatch,
        matching: find.textContaining('Card owned-only'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Card owned-only'), findsOneWidget);
    expect(find.textContaining('Card unowned-only'), findsOneWidget);
  });

  testWidgets('shows an ownership badge on a candidate that is owned', (
    tester,
  ) async {
    final owned = _candidate(cardId: 'owned', isOwned: true, savings: 100);
    final recommendation = MovieDealsRecommendation(
      candidates: [owned],
      rejectedCandidates: const [],
      guaranteedOwned: [owned],
      guaranteedOverall: [owned],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You own this'), findsOneWidget);
  });

  testWidgets('renders every bank and card variant in its own option box', (
    tester,
  ) async {
    final axis = _candidate(
      cardId: 'atlas',
      bankName: 'Axis Bank',
      isOwned: true,
      savings: 100,
    );
    final idfc = _candidate(
      cardId: 'mayura',
      bankName: 'IDFC FIRST Bank',
      isOwned: true,
      savings: 80,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [axis, idfc],
      rejectedCandidates: const [],
      guaranteedOwned: [axis, idfc],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('movie-card-option-atlas')), findsOneWidget);
    expect(find.byKey(const Key('movie-card-option-mayura')), findsOneWidget);
    expect(find.text('Axis Bank'), findsOneWidget);
    expect(find.text('Card atlas'), findsOneWidget);
    expect(find.text('IDFC FIRST Bank'), findsOneWidget);
    expect(find.text('Card mayura'), findsOneWidget);
  });

  testWidgets(
    'falls back to potential groups when no guaranteed candidate exists',
    (tester) async {
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(const MovieDealsResults(request: request)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Card potential-only'), findsWidgets);
      // The guaranteed tiles must show their empty-state note, not the
      // potential candidate presented as if it were guaranteed.
      expect(find.textContaining('No guaranteed'), findsWidgets);
    },
  );

  testWidgets(
    'shows an empty-state note for a group with zero eligible candidates, never hides the tile',
    (tester) async {
      final overallOnly = _candidate(
        cardId: 'overall-only',
        isOwned: false,
        savings: 100,
      );
      final recommendation = MovieDealsRecommendation(
        candidates: [overallOnly],
        rejectedCandidates: const [],
        guaranteedOverall: [overallOnly],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(const MovieDealsResults(request: request)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('GUARANTEED · YOU OWN'), findsOneWidget);
      expect(
        find.textContaining('No guaranteed deals on cards you own'),
        findsOneWidget,
      );
      expect(find.textContaining('POTENTIAL · YOU OWN'), findsOneWidget);
      expect(
        find.textContaining('No potential deals on cards you own'),
        findsOneWidget,
      );
      expect(find.textContaining('POTENTIAL · OVERALL'), findsOneWidget);
      expect(
        find.textContaining('No potential deals available'),
        findsOneWidget,
      );
    },
  );

  testWidgets('renders the only populated option as a full-width best match', (
    tester,
  ) async {
    final potential = _candidate(
      cardId: 'only-populated',
      isOwned: false,
      savings: 200,
      platformConfidence: MovieDealPlatformConfidence.unconfirmed,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [potential],
      rejectedCandidates: const [],
      potentialOverall: [potential],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    final bestMatch = find.byKey(const Key('movie-best-match'));
    expect(bestMatch, findsOneWidget);
    expect(
      tester.getSize(bestMatch).width,
      tester.getSize(find.byType(MovieDealsResults)).width,
    );
    expect(find.byKey(const Key('movie-empty-groups-summary')), findsOneWidget);
  });

  testWidgets(
    'shows a single no-deal message when every group and every dedicated section is empty',
    (tester) async {
      const recommendation = MovieDealsRecommendation(
        candidates: [],
        rejectedCandidates: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(const MovieDealsResults(request: request)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No eligible ticket-saving option'), findsOneWidget);
    },
  );

  testWidgets('shows a retryable unavailable message on repository failure', (
    tester,
  ) async {
    const recommendation = MovieDealsRecommendation(
      candidates: [],
      rejectedCandidates: [],
      status: MovieDealsStatus.unavailable,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('unavailable'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Retry'), findsOneWidget);
  });

  testWidgets(
    'a rewardMultiplier candidate renders its raw rate, never a computed rupee figure',
    (tester) async {
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(const MovieDealsResults(request: request)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('points program'), findsOneWidget);
      expect(find.textContaining('Save ₹0'), findsNothing);
    },
  );

  testWidgets(
    'an annualAllowance candidate renders in its own strip, never in a ranked group',
    (tester) async {
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
        explanation:
            'Up to ₹6000/year in movie tickets — remaining balance not tracked.',
      );
      final recommendation = MovieDealsRecommendation(
        candidates: [annualCandidate],
        rejectedCandidates: const [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(const MovieDealsResults(request: request)),
        ),
      );
      await tester.pumpAndSettle();

      // "balance not tracked" legitimately appears twice — once in the
      // tile title, once in the candidate's own explanation text — so
      // assert on the more specific candidate-level string instead.
      expect(
        find.textContaining('remaining balance not tracked'),
        findsOneWidget,
      );
      expect(find.textContaining('Save ₹0'), findsNothing);
    },
  );

  testWidgets(
    'names the searched platform on a candidate whose rule is tied to it',
    (tester) async {
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              searchedRequest,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(
            const MovieDealsResults(request: searchedRequest),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('BookMyShow'), findsWidgets);
    },
  );

  testWidgets('displays Zomato movie offers as Zomato/District', (
    tester,
  ) async {
    final zomato = _candidate(
      cardId: 'zomato-card',
      isOwned: false,
      savings: 300,
      partners: {'zomato'},
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [zomato],
      rejectedCandidates: const [],
      potentialOverall: [zomato],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Zomato/District'), findsOneWidget);
    expect(find.text('Eligible booking platform: Zomato.'), findsNothing);
  });

  testWidgets(
    'does not claim a platform tie when the rule is tied to a different platform',
    (tester) async {
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

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              searchedRequest,
            ).overrideWith((ref) async => recommendation),
            // This candidate's non-explicit platformConfidence + a searched
            // preferredPlatform makes confirmCallbackFor try to read
            // currentUserProvider, which reaches Supabase.instance — not
            // initialized in this widget test.
            currentUserProvider.overrideWithValue(null),
          ],
          child: _wideHarness(
            const MovieDealsResults(request: searchedRequest),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not tied to PVR'), findsWidgets);
      expect(find.textContaining('Available on BookMyShow'), findsWidgets);
      expect(find.text('Save ₹100'), findsNothing);
      expect(find.text('₹900'), findsNothing);
    },
  );

  testWidgets(
    'shows an honest cinema-not-supported note only when a cinema was searched',
    (tester) async {
      const searchedRequest = MovieTicketRequest(
        numberOfTickets: 2,
        pricePerTicket: 300,
        preferredCinema: 'PVR Phoenix',
      );
      final candidate = _candidate(
        cardId: 'cinema-card',
        isOwned: true,
        savings: 100,
      );
      final recommendation = MovieDealsRecommendation(
        candidates: [candidate],
        rejectedCandidates: const [],
        guaranteedOwned: [candidate],
        guaranteedOverall: [candidate],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              searchedRequest,
            ).overrideWith((ref) async => recommendation),
          ],
          child: _wideHarness(
            const MovieDealsResults(request: searchedRequest),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Cinema filtering is not yet supported'),
        findsWidgets,
      );
    },
  );

  testWidgets('omits the cinema note entirely when no cinema was searched', (
    tester,
  ) async {
    final candidate = _candidate(
      cardId: 'no-cinema-card',
      isOwned: true,
      savings: 100,
    );
    final recommendation = MovieDealsRecommendation(
      candidates: [candidate],
      rejectedCandidates: const [],
      guaranteedOwned: [candidate],
      guaranteedOverall: [candidate],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          movieDealsSearchProvider(
            request,
          ).overrideWith((ref) async => recommendation),
        ],
        child: _wideHarness(const MovieDealsResults(request: request)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cinema filtering'), findsNothing);
  });
}
