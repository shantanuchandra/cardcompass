import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_evaluator.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';
import 'package:cardcompass/features/benefits/movie_deals/providers/movie_deals_provider.dart';
import 'package:cardcompass/features/benefits/movie_deals/screens/movie_deals_results.dart';
import 'package:cardcompass/features/benefits/movie_deals/screens/movie_deals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _request = MovieTicketRequest(
  numberOfTickets: 2,
  pricePerTicket: 500,
  preferredPlatform: 'BookMyShow',
);

MovieDealCandidate get _winner => evaluateMovieDeals(
  request: _request,
  rules: [
    MovieDealRule(
      benefitId: 'movie-benefit',
      catalogCardId: 'owned-card',
      title: '25% Off on Movie Tickets',
      offerType: MovieDealOfferType.percentDiscount,
      cardName: 'Horizon Movie Card',
      discountPercent: 25,
      partners: const {'BookMyShow'},
    ),
  ],
  contexts: {
    ('owned-card', 'movie-benefit'): const MovieDealContext(isOwned: true),
  },
  now: DateTime(2026, 8, 16),
).bestGuaranteedOwned!;

MovieDealCandidate get _potentialBogo => evaluateMovieDeals(
  request: _request,
  rules: [
    MovieDealRule(
      benefitId: 'bogo-benefit',
      catalogCardId: 'bogo-card',
      title: 'Twin ticket treats',
      offerType: MovieDealOfferType.bogo,
      cardName: 'Horizon BOGO Card',
      partners: const {'BookMyShow'},
      buyCount: 1,
      freeCount: 1,
      perTransactionCap: 500,
      cycleRedemptionLimit: 2,
    ),
  ],
  contexts: {
    ('bogo-card', 'bogo-benefit'): const MovieDealContext(isOwned: true),
  },
  now: DateTime(2026, 8, 16),
).bestPotentialOwned!;

Future<void> pumpMovieDeals(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: MovieDealsScreen()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pumps both slots stacked — matching how movie_deals_screen.dart
/// actually composes them (form + owned on the left, overall on the
/// right at desktop widths, stacked at mobile widths) — so assertions
/// check what a real search actually renders, not one slot in isolation.
Future<void> pumpMovieResult(
  WidgetTester tester, {
  double width = 390,
  double textScale = 1,
  MovieTicketRequest request = _request,
  MovieDealsRecommendation? recommendation,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final result =
      recommendation ??
      MovieDealsRecommendation(
        candidates: [_winner],
        rejectedCandidates: const [],
        bestGuaranteedOwned: _winner,
        bestGuaranteedOverall: _winner,
        guaranteedOwned: [_winner],
        guaranteedOverall: [_winner],
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        movieDealsSearchProvider(request).overrideWith((ref) async => result),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  MovieDealsResults(request: request, slot: ResultsSlot.owned),
                  MovieDealsResults(request: request, slot: ResultsSlot.overall),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('movie form asks plain-language questions', (tester) async {
    await pumpMovieDeals(tester, width: 390);

    expect(find.text('How many tickets?'), findsOneWidget);
    expect(find.text('Price per ticket'), findsOneWidget);
    expect(find.text('Where are you booking?'), findsOneWidget);
    expect(find.text('Which cinema?'), findsOneWidget);
    expect(find.textContaining('TICKET SPECIFICATIONS'), findsNothing);
  });

  testWidgets('movie form action text uses the shared type floor', (
    tester,
  ) async {
    await pumpMovieDeals(tester, width: 390);

    expect(
      tester.widget<Text>(find.text('2 TICKETS')).style?.fontSize,
      greaterThanOrEqualTo(14),
    );
    expect(
      tester.widget<Text>(find.text('Find my best option')).style?.fontSize,
      greaterThanOrEqualTo(14),
    );
    expect(
      tester
          .widget<Text>(find.text('Offers checked against current rules'))
          .style
          ?.fontSize,
      greaterThanOrEqualTo(12),
    );

    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) => widget is DropdownButtonFormField<String>,
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Any platform').last).style?.fontSize,
      greaterThanOrEqualTo(14),
    );
  });

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'movie form keeps questions usable at ${width.toInt()}px / $textScale×',
        (tester) async {
          await pumpMovieDeals(tester, width: width, textScale: textScale);

          final tickets = find.byKey(const Key('ticket-count-question'));
          final price = find.byKey(const Key('ticket-price-question'));
          final ticketsTopLeft = tester.getTopLeft(tickets);
          final priceTopLeft = tester.getTopLeft(price);
          final shouldStack = width < 600 || textScale >= 1.5;
          if (shouldStack) {
            expect(priceTopLeft.dy, greaterThan(ticketsTopLeft.dy));
          } else {
            expect(priceTopLeft.dx, greaterThan(ticketsTopLeft.dx));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final width in [390.0, 768.0, 1280.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'movie recommendation remains usable at ${width.toInt()}px / $textScale×',
        (tester) async {
          await pumpMovieResult(tester, width: width, textScale: textScale);

          expect(find.text('Guaranteed · You own'), findsOneWidget);
          expect(find.text('Guaranteed · Overall'), findsOneWidget);
          expect(find.textContaining('Save ₹'), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('result names a usable route and translates evaluator jargon', (
    tester,
  ) async {
    await pumpMovieResult(tester);

    expect(find.textContaining('Horizon Movie Card'), findsWidgets);
    expect(find.text('Tied to BookMyShow.'), findsWidgets);
    expect(
      find.text('This offer takes 25% off the ticket total.'),
      findsWidgets,
    );
    expect(find.textContaining('percentDiscount saves'), findsNothing);
    expect(find.textContaining('unverified usage'), findsNothing);
  });

  testWidgets('result is honest when an eligible booking platform is unknown', (
    tester,
  ) async {
    const requestWithoutPlatform = MovieTicketRequest(
      numberOfTickets: 2,
      pricePerTicket: 500,
    );
    final unknownPlatform = evaluateMovieDeals(
      request: requestWithoutPlatform,
      rules: [
        MovieDealRule(
          benefitId: 'unknown-platform-benefit',
          catalogCardId: 'unknown-platform-card',
          title: '10% off',
          offerType: MovieDealOfferType.percentDiscount,
          cardName: 'Horizon Unknown Platform Card',
          discountPercent: 10,
        ),
      ],
      contexts: {
        ('unknown-platform-card', 'unknown-platform-benefit'):
            const MovieDealContext(isOwned: true),
      },
      now: DateTime(2026, 8, 16),
    ).bestPotentialOwned!;
    final recommendation = MovieDealsRecommendation(
      candidates: [unknownPlatform],
      rejectedCandidates: const [],
      bestPotentialOwned: unknownPlatform,
      bestPotentialOverall: unknownPlatform,
      potentialOwned: [unknownPlatform],
      potentialOverall: [unknownPlatform],
    );

    await pumpMovieResult(
      tester,
      request: requestWithoutPlatform,
      recommendation: recommendation,
    );

    // Appears in BOTH slots — this candidate is both the owned and
    // overall potential winner, so it renders in both columns.
    expect(
      find.text('Booking platform is not confirmed for this offer.'),
      findsNWidgets(2),
    );
  });

  testWidgets(
    'potential routes are never presented as verified and disclose monthly caps at 390px / 2x',
    (tester) async {
      final potential = _potentialBogo;
      final recommendation = MovieDealsRecommendation(
        candidates: [potential],
        rejectedCandidates: const [],
        bestPotentialOwned: potential,
        bestPotentialOverall: potential,
        potentialOwned: [potential],
        potentialOverall: [potential],
      );

      await pumpMovieResult(
        tester,
        width: 390,
        textScale: 2,
        recommendation: recommendation,
      );

      expect(find.text('Potential · You own'), findsOneWidget);
      expect(find.text('Potential · Overall'), findsOneWidget);
      expect(find.textContaining('Buy 1 ticket and get 1 free'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guaranteed and potential groups are explicitly separated by section, never mixed',
    (tester) async {
      final potential = _potentialBogo;
      final recommendation = MovieDealsRecommendation(
        candidates: [_winner, potential],
        rejectedCandidates: const [],
        bestGuaranteedOwned: _winner,
        bestGuaranteedOverall: _winner,
        bestPotentialOwned: potential,
        bestPotentialOverall: potential,
        guaranteedOwned: [_winner],
        guaranteedOverall: [_winner],
        potentialOwned: [potential],
        potentialOverall: [potential],
      );

      await pumpMovieResult(tester, recommendation: recommendation);

      expect(find.text('Guaranteed · You own'), findsOneWidget);
      expect(find.text('Potential · You own'), findsOneWidget);
      expect(find.textContaining('Horizon Movie Card'), findsWidgets);
      expect(find.textContaining('Horizon BOGO Card'), findsWidgets);
    },
  );
}
