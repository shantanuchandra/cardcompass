import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_rule.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/movie_deal_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 15);

  MovieTicketRequest request(int tickets, double price) => MovieTicketRequest(
        numberOfTickets: tickets,
        pricePerTicket: price,
        preferredPlatform: 'BookMyShow',
        preferredCinema: 'PVR',
      );

  MovieDealRule rule({
    required String cardId,
    required MovieDealOfferType type,
    int priority = 0,
    int? buyCount,
    int? freeCount,
    double? percent,
    double? fixed,
    double? cap,
    double? minimum,
    DateTime? start,
    DateTime? end,
    Set<String> platforms = const {},
    Set<String> cinemas = const {},
    Set<String> weekdays = const {},
    Set<String> exclusions = const {},
    int? ticketLimit,
    int? cycleTicketLimit,
    int? cycleTransactionLimit,
    double? milestoneThreshold,
    double? milestoneReward,
  }) =>
      MovieDealRule(
        benefitId: 'benefit-$cardId',
        catalogCardId: cardId,
        title: cardId,
        offerType: type,
        displayPriority: priority,
        buyCount: buyCount,
        freeCount: freeCount,
        discountPercent: percent,
        fixedAmount: fixed,
        maximumDiscount: cap,
        minimumTransaction: minimum,
        validityStart: start,
        validityEnd: end,
        platforms: platforms,
        cinemas: cinemas,
        validWeekdays: weekdays,
        exclusions: exclusions,
        transactionTicketLimit: ticketLimit,
        cycleTicketLimit: cycleTicketLimit,
        cycleTransactionLimit: cycleTransactionLimit,
        milestoneThreshold: milestoneThreshold,
        milestoneReward: milestoneReward,
      );

  test('calculates four ₹300 BOGO tickets as ₹600 saving', () {
    final result = evaluateMovieDeals(
      request: request(4, 300),
      rules: [
        rule(
            cardId: 'owned-card',
            type: MovieDealOfferType.bogo,
            buyCount: 1,
            freeCount: 1)
      ],
      contexts: const {'owned-card': MovieDealContext(isOwned: true)},
      now: today,
    );

    expect(result.bestOwned!.savings, 600);
    expect(result.bestOwned!.finalAmount, 600);
  });

  test('keeps owned and overall winners independent', () {
    final result = evaluateMovieDeals(
      request: request(2, 300),
      rules: [
        rule(
            cardId: 'owned-card',
            type: MovieDealOfferType.percentDiscount,
            percent: 10),
        rule(
            cardId: 'unowned-card',
            type: MovieDealOfferType.bogo,
            buyCount: 1,
            freeCount: 1),
      ],
      contexts: const {
        'owned-card': MovieDealContext(isOwned: true),
        'unowned-card': MovieDealContext(),
      },
      now: today,
    );

    expect(result.bestOwned!.cardId, 'owned-card');
    expect(result.bestOverall!.cardId, 'unowned-card');
  });

  test('applies fixed, cashback, and declared caps without exceeding spend',
      () {
    final result = evaluateMovieDeals(
      request: request(2, 300),
      rules: [
        rule(
            cardId: 'fixed',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 900),
        rule(
            cardId: 'cashback',
            type: MovieDealOfferType.cashback,
            percent: 50,
            cap: 200),
      ],
      contexts: const {
        'fixed': MovieDealContext(),
        'cashback': MovieDealContext()
      },
      now: today,
    );

    expect(result.candidates[0].cardId, 'fixed');
    expect(result.candidates[0].savings, 600);
    expect(result.candidates[1].savings, 200);
  });

  test('rejects expired and mismatched platform or cinema rules', () {
    final result = evaluateMovieDeals(
      request: request(2, 300),
      rules: [
        rule(
            cardId: 'expired',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            end: DateTime(2026, 7, 14)),
        rule(
            cardId: 'platform',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            platforms: {'Paytm'}),
        rule(
            cardId: 'cinema',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            cinemas: {'INOX'}),
      ],
      contexts: const {},
      now: today,
    );

    expect(result.candidates, isEmpty);
    expect(result.rejectedCandidates, hasLength(3));
  });

  test('enforces weekday, exclusions, minimum spend, and ticket limits', () {
    final result = evaluateMovieDeals(
      request: request(2, 300),
      rules: [
        rule(
            cardId: 'weekday',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            weekdays: {'monday'}),
        rule(
            cardId: 'excluded',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            exclusions: {'PVR'}),
        rule(
            cardId: 'minimum',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            minimum: 601),
        rule(
            cardId: 'tickets',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 10,
            ticketLimit: 1),
      ],
      contexts: const {},
      now: today,
    );

    expect(result.candidates, isEmpty);
    expect(result.rejectedCandidates, hasLength(4));
  });

  test(
      'requires verified milestone spend and rejects exhausted verified limits',
      () {
    final result = evaluateMovieDeals(
      request: request(2, 300),
      rules: [
        rule(
            cardId: 'milestone',
            type: MovieDealOfferType.freeTickets,
            milestoneThreshold: 1000,
            milestoneReward: 2),
        rule(
            cardId: 'limited',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 100,
            cycleTicketLimit: 2),
      ],
      contexts: const {
        'milestone': MovieDealContext(isOwned: true, milestoneSpend: 1000),
        'limited': MovieDealContext(
            usageConfidence: MovieDealUsageConfidence.verified, usedTickets: 2),
      },
      now: today,
    );

    expect(result.bestOwned!.savings, 600);
    expect(result.rejectedCandidates.single.cardId, 'limited');
  });

  test('rejects verified cycle limits that cannot cover the request tickets',
      () {
    final result = evaluateMovieDeals(
      request: request(2, 300),
      rules: [
        rule(
          cardId: 'limited',
          type: MovieDealOfferType.bogo,
          buyCount: 1,
          freeCount: 1,
          cycleTicketLimit: 2,
        ),
      ],
      contexts: const {
        'limited': MovieDealContext(
          usageConfidence: MovieDealUsageConfidence.verified,
          usedTickets: 1,
        ),
      },
      now: today,
    );

    expect(result.candidates, isEmpty);
    expect(result.rejectedCandidates.single.reason,
        'Ticket limit for this request is exceeded.');
  });

  test('sanitizes negative ticket counts before evaluating spend and savings',
      () {
    final result = evaluateMovieDeals(
      request: request(-2, 300),
      rules: [
        rule(
          cardId: 'minimum',
          type: MovieDealOfferType.percentDiscount,
          percent: 10,
          minimum: 1,
        ),
      ],
      contexts: const {},
      now: today,
    );

    expect(result.candidates, isEmpty);
    expect(
        result.rejectedCandidates.single.reason, 'Minimum spend is not met.');
  });

  test('sanitizes negative ticket prices before evaluating spend and savings',
      () {
    final result = evaluateMovieDeals(
      request: request(2, -300),
      rules: [
        rule(
          cardId: 'minimum',
          type: MovieDealOfferType.percentDiscount,
          percent: 10,
          minimum: 1,
        ),
      ],
      contexts: const {},
      now: today,
    );

    expect(result.candidates, isEmpty);
    expect(
        result.rejectedCandidates.single.reason, 'Minimum spend is not met.');
  });

  test('does not make two negative request values eligible or profitable', () {
    final result = evaluateMovieDeals(
      request: request(-2, -300),
      rules: [
        rule(
          cardId: 'minimum',
          type: MovieDealOfferType.percentDiscount,
          percent: 10,
          minimum: 1,
        ),
      ],
      contexts: const {},
      now: today,
    );

    expect(result.candidates, isEmpty);
    expect(
        result.rejectedCandidates.single.reason, 'Minimum spend is not met.');
  });

  test('uses deterministic ties after confidence and display priority', () {
    final result = evaluateMovieDeals(
      request: request(1, 300),
      rules: [
        rule(
            cardId: 'z-card',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 100,
            priority: 1),
        rule(
            cardId: 'a-card',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 100,
            priority: 1),
        rule(
            cardId: 'verified-card',
            type: MovieDealOfferType.fixedDiscount,
            fixed: 100),
      ],
      contexts: const {
        'z-card': MovieDealContext(),
        'a-card': MovieDealContext(),
        'verified-card': MovieDealContext(
            usageConfidence: MovieDealUsageConfidence.verified),
      },
      now: today,
    );

    expect(result.bestOverall!.cardId, 'verified-card');
    expect(result.candidates.skip(1).first.cardId, 'a-card');
  });
}
