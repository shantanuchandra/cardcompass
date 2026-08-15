import 'package:cardcompass/core/theme/app_theme.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';
import 'package:cardcompass/features/benefits/movie_deals/providers/movie_deals_provider.dart';
import 'package:cardcompass/features/benefits/movie_deals/screens/movie_deals_results.dart';
import 'package:cardcompass/features/benefits/movie_deals/screens/movie_deals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _request = MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 500);

final _winner = MovieDealCandidate(
  cardId: 'owned-card',
  benefitId: 'movie-benefit',
  title: 'Movie tickets',
  rule: MovieDealRule(
    benefitId: 'movie-benefit',
    catalogCardId: 'owned-card',
    title: 'Movie tickets',
    offerType: MovieDealOfferType.percentDiscount,
    cardName: 'Horizon Movie Card',
    discountPercent: 30,
    perTransactionCap: 300,
  ),
  isOwned: true,
  grossAmount: 1000,
  savings: 300,
  finalAmount: 700,
  usageConfidence: MovieDealUsageConfidence.verified,
  platformConfidence: MovieDealPlatformConfidence.explicit,
  explanation: 'Your card gives 30% off this booking.',
);

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

Future<void> pumpMovieResult(
  WidgetTester tester, {
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final recommendation = MovieDealsRecommendation(
    candidates: [_winner],
    rejectedCandidates: const [],
    bestGuaranteedOwned: _winner,
    bestGuaranteedOverall: _winner,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        movieDealsSearchProvider(
          _request,
        ).overrideWith((ref) async => recommendation),
      ],
      child: MaterialApp(
        theme: AppTheme.work,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: const Scaffold(body: MovieDealsResults(request: _request)),
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

          expect(find.text('Best option'), findsOneWidget);
          expect(find.text('Expected saving'), findsOneWidget);
          expect(find.text('Effective ticket price'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('result leads with recommendation and hides calculation detail', (
    tester,
  ) async {
    await pumpMovieResult(tester);

    expect(find.text('Best option'), findsOneWidget);
    expect(find.text('Expected saving'), findsOneWidget);
    expect(find.text('Effective ticket price'), findsOneWidget);
    expect(find.text('Show calculation'), findsOneWidget);
    expect(find.text('Booking total'), findsNothing);

    await tester.tap(find.text('Show calculation'));
    await tester.pumpAndSettle();
    expect(find.text('Booking total'), findsOneWidget);
  });
}
