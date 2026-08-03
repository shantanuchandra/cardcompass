// test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_candidate.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_evaluator.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_deal_rule.dart';
import 'package:cardcompass/features/benefits/movie_deals/domain/movie_ticket_request.dart';

MovieDealRule _bogoRule({String cardId = 'c1', Set<String> partners = const {}}) => MovieDealRule(
      benefitId: 'b-bogo',
      catalogCardId: cardId,
      title: 'Twin ticket treats',
      offerType: MovieDealOfferType.bogo,
      partners: partners,
      buyCount: 1,
      freeCount: 1,
      perTransactionCap: 500,
      cycleRedemptionLimit: 2,
    );

MovieDealRule _percentRule({String cardId = 'c2', double percent = 10, Set<String> partners = const {}}) =>
    MovieDealRule(
      benefitId: 'b-percent',
      catalogCardId: cardId,
      title: '10% off',
      offerType: MovieDealOfferType.percentDiscount,
      discountPercent: percent,
      partners: partners,
    );

MovieDealRule _milestoneRule({String cardId = 'c3', Set<String> partners = const {}}) => MovieDealRule(
      benefitId: 'b-milestone',
      catalogCardId: cardId,
      title: 'Monthly Vouchers',
      offerType: MovieDealOfferType.milestone,
      milestoneThreshold: 80000,
      milestoneReward: 500,
      partners: partners,
    );

MovieDealRule _fixedDiscountWithCapRule({String cardId = 'c4'}) => MovieDealRule(
      benefitId: 'b-fixed',
      catalogCardId: cardId,
      title: 'BookMyShow Discount',
      offerType: MovieDealOfferType.fixedDiscount,
      fixedAmount: 1500,
      cycleAmountCap: 1500,
      partners: const {'BookMyShow'},
    );

void main() {
  final today = DateTime(2026, 8, 2);

  group('bogo savings math', () {
    test('per-transaction cap of 500 clamps a lower-priced pair to the full ticket price', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 400),
        rules: [_bogoRule()],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, 400);
      expect(candidate.finalAmount, 400);
    });

    test('per-transaction cap of 500 clamps when the second ticket exceeds the cap', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 600),
        rules: [_bogoRule()],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, 500);
      expect(candidate.finalAmount, 700);
    });
  });

  group('percentDiscount savings math', () {
    test('4 tickets at 300 with 10% off saves 120', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300),
        rules: [_percentRule(percent: 10)],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.savings, 120);
      expect(candidate.finalAmount, 1080);
    });
  });

  group('guaranteed-tier gate — data-availability limit (design spec §5/§7)', () {
    test('a bogo candidate with verified-looking usage still never reaches the guaranteed tier', () {
      // Even with usageConfidence forced to verified in the context (simulating
      // a hypothetical future signal), bogo ALWAYS carries a cycleRedemptionLimit
      // in real data, so it needs verified usage AND explicit platform — this
      // test proves the GATE logic, not that verified is unreachable (Task 11
      // proves verified is unreachable from real repository data).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'Zomato'),
        rules: [_bogoRule(partners: {'Zomato'})],
        contexts: {
          'c1': const MovieDealContext(isOwned: true, usageConfidence: MovieDealUsageConfidence.unverified),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
      expect(result.bestPotentialOwned!.cardId, 'c1');
    });

    test('a percentDiscount candidate with verified usage and explicit platform reaches the guaranteed tier', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_percentRule(percent: 10, partners: {'BookMyShow'})],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNotNull);
      expect(result.bestGuaranteedOwned!.cardId, 'c2');
    });

    test('a milestone candidate never reaches the guaranteed tier, regardless of milestoneSpend', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'BookMyShow'})],
        contexts: {
          'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
    });

    test('a fixedDiscount candidate with a cycleAmountCap never reaches the guaranteed tier', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_fixedDiscountWithCapRule()],
        contexts: {'c4': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
    });
  });

  group('platform confidence uses eligibleMoviePlatforms, never raw partners', () {
    test('searching "Uber" against the multi-partner milestone rule does NOT yield explicit confidence', () {
      // partners: {Uber, cult.fit Live, BookMyShow, TataCliQ} but
      // eligibleMoviePlatforms only ever resolves to {BookMyShow} (design
      // spec §5/§8 regression requirement).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'Uber'),
        rules: [_milestoneRule(partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'})],
        contexts: {'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c3');
      expect(candidate.platformConfidence, isNot(MovieDealPlatformConfidence.explicit));
    });

    test('searching "BookMyShow" against the same rule DOES yield explicit confidence', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'})],
        contexts: {'c3': const MovieDealContext(isOwned: true, milestoneSpend: 85000)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c3');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.explicit);
    });
  });

  group('notRequested confidence and its precedence with communityConfirmed', () {
    test('empty eligibleMoviePlatforms, no platform requested, no confirmations => notRequested', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [_percentRule()], // no partners
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.notRequested);
    });

    test('empty eligibleMoviePlatforms, no platform requested, but a confirmation exists => communityConfirmed, never notRequested', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300),
        rules: [_percentRule()],
        contexts: {
          'c2': const MovieDealContext(isOwned: true, confirmedPlatforms: {'PVR'}),
        },
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.communityConfirmed);
    });

    test('empty eligibleMoviePlatforms, a SPECIFIC platform requested, no confirmations => unconfirmed, never notRequested', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'PVR'),
        rules: [_percentRule()],
        contexts: {'c2': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.platformConfidence, MovieDealPlatformConfidence.unconfirmed);
    });
  });

  group('independent owned/overall ranking within each tier', () {
    test('keeps guaranteed owned and overall winners independent — no ownership bonus', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [
          _percentRule(cardId: 'owned-card', percent: 5, partners: {'BookMyShow'}),
          _percentRule(cardId: 'unowned-card', percent: 20, partners: {'BookMyShow'}),
        ],
        contexts: {
          'owned-card': const MovieDealContext(isOwned: true),
          'unowned-card': const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned!.cardId, 'owned-card');
      expect(result.bestGuaranteedOverall!.cardId, 'unowned-card');
      expect(result.bestGuaranteedOverall!.savings, greaterThan(result.bestGuaranteedOwned!.savings));
    });

    test('shared winner appears as the same candidate in both guaranteed fields', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_percentRule(cardId: 'c1', percent: 10, partners: {'BookMyShow'})],
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned!.cardId, result.bestGuaranteedOverall!.cardId);
      expect(result.bestGuaranteedOwned!.benefitId, result.bestGuaranteedOverall!.benefitId);
    });
  });

  group('rewardMultiplier never gets a computed rupee savings figure', () {
    test('rewardMultiplier candidate has zero computed savings', () {
      final multiplierRule = MovieDealRule(
        benefitId: 'b-mult',
        catalogCardId: 'c5',
        title: '10X points',
        offerType: MovieDealOfferType.rewardMultiplier,
        rewardMultiplierRate: 10,
        rewardMultiplierUnit: 'points per Rs.150',
        qualifyingCategories: const {'movies'},
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [multiplierRule],
        contexts: {'c5': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c5');
      expect(candidate.savings, 0);
    });
  });

  group('never invents commercial terms', () {
    test('savings are always clamped to eligible spend, never negative', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 100),
        rules: [_bogoRule()], // cap of 500 far exceeds a 100-rupee ticket
        contexts: {'c1': const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, lessThanOrEqualTo(100));
      expect(candidate.savings, greaterThanOrEqualTo(0));
    });
  });
}
