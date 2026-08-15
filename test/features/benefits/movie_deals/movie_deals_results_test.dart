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
  MovieDealPlatformConfidence platformConfidence =
      MovieDealPlatformConfidence.explicit,
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

  testWidgets(
    'leads with the owned recommendation and compares the overall alternative',
    (tester) async {
      final owned = _candidate(cardId: 'owned', isOwned: true, savings: 100);
      final overall = _candidate(
        cardId: 'unowned',
        isOwned: false,
        savings: 300,
      );
      final recommendation = MovieDealsRecommendation(
        candidates: [overall, owned],
        rejectedCandidates: const [],
        bestGuaranteedOwned: owned,
        bestGuaranteedOverall: overall,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MovieDealsResults(request: request)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Best option'), findsOneWidget);
      expect(find.text('Other eligible options'), findsOneWidget);
      expect(find.textContaining('Card owned'), findsOneWidget);
      expect(find.textContaining('Card unowned'), findsOneWidget);
    },
  );

  testWidgets(
    'shows one best option when the same card wins both guaranteed pools',
    (tester) async {
      final winner = _candidate(cardId: 'shared', isOwned: true, savings: 300);
      final recommendation = MovieDealsRecommendation(
        candidates: [winner],
        rejectedCandidates: const [],
        bestGuaranteedOwned: winner,
        bestGuaranteedOverall: winner,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MovieDealsResults(request: request)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Best option'), findsOneWidget);
      expect(find.text('Other eligible options'), findsNothing);
      expect(find.textContaining('Card shared'), findsOneWidget);
    },
  );

  testWidgets(
    'falls back to a labeled potential candidate when no guaranteed winner exists',
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
        bestPotentialOwned: potential,
        bestPotentialOverall: potential,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            movieDealsSearchProvider(
              request,
            ).overrideWith((ref) async => recommendation),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MovieDealsResults(request: request)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Card potential-only'), findsWidgets);
      expect(find.textContaining('Potential'), findsWidgets);
      expect(find.text('Best option'), findsOneWidget);
      expect(
        find.textContaining('check availability and remaining usage'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows a no-deal message when neither tier has a winner', (
    tester,
  ) async {
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
        child: const MaterialApp(
          home: Scaffold(body: MovieDealsResults(request: request)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No eligible ticket-saving option'), findsOneWidget);
  });

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
        child: const MaterialApp(
          home: Scaffold(body: MovieDealsResults(request: request)),
        ),
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
          child: const MaterialApp(
            home: Scaffold(body: MovieDealsResults(request: request)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('points program'), findsOneWidget);
      expect(find.textContaining('Save ₹0'), findsNothing);
    },
  );
}
