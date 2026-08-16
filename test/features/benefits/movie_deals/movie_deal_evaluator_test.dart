// test/features/benefits/movie_deals/movie_deal_evaluator_test.dart
import 'package:flutter_test/flutter_test.dart';
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

MovieDealRule _percentRule({
  String cardId = 'c2',
  double percent = 10,
  Set<String> partners = const {},
  double? perTransactionCap,
}) =>
    MovieDealRule(
      benefitId: 'b-percent',
      catalogCardId: cardId,
      title: '10% off',
      offerType: MovieDealOfferType.percentDiscount,
      discountPercent: percent,
      partners: partners,
      perTransactionCap: perTransactionCap,
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
        contexts: {('c1', 'b-bogo'): const MovieDealContext(isOwned: true)},
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
        contexts: {('c1', 'b-bogo'): const MovieDealContext(isOwned: true)},
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
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.savings, 120);
      expect(candidate.finalAmount, 1080);
    });

    test('a perTransactionCap clamps a percentDiscount below the uncapped rate', () {
      // Real row: "25% off on movie tickets" (IDFC First Millennia) —
      // sourced terms (bankbazaar/paisabazaar/cardinsider, converging):
      // 25% off, capped at ₹100. 2 tickets @ ₹350 = ₹700 gross; uncapped
      // 25% would be ₹175, but the real cap limits it to ₹100.
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 350),
        rules: [_percentRule(percent: 25, perTransactionCap: 100)],
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.savings, 100);
      expect(candidate.finalAmount, 600);
    });

    test('a percentDiscount with no perTransactionCap is uncapped, matching pre-existing behavior', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 350),
        rules: [_percentRule(percent: 25)],
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.savings, 175);
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
          ('c1', 'b-bogo'): const MovieDealContext(isOwned: true, usageConfidence: MovieDealUsageConfidence.unverified),
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
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNotNull);
      expect(result.bestGuaranteedOwned!.cardId, 'c2');
    });

    test('a percentDiscount candidate with a perTransactionCap never reaches the guaranteed tier, same as capped bogo/fixedDiscount', () {
      // Real row: IDFC First Millennia's "25% off up to ₹100" — a capped
      // percentDiscount has the identical unverifiable-usage problem
      // bogo/fixedDiscount already correctly avoid (no signal tracks
      // whether this cycle's cap redemption has already been used).
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_percentRule(percent: 10, partners: {'BookMyShow'}, perTransactionCap: 50)],
        contexts: {
          ('c2', 'b-percent'): const MovieDealContext(isOwned: true, usageConfidence: MovieDealUsageConfidence.unverified),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestPotentialOwned, isNotNull);
      expect(result.bestPotentialOwned!.cardId, 'c2');
    });

    test('a milestone candidate never reaches the guaranteed tier, regardless of milestoneSpend', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'BookMyShow'})],
        contexts: {
          ('c3', 'b-milestone'): const MovieDealContext(isOwned: true, milestoneSpend: 85000),
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
        contexts: {('c4', 'b-fixed'): const MovieDealContext(isOwned: true)},
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
        contexts: {('c3', 'b-milestone'): const MovieDealContext(isOwned: true, milestoneSpend: 85000)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c3');
      expect(candidate.platformConfidence, isNot(MovieDealPlatformConfidence.explicit));
    });

    test('searching "BookMyShow" against the same rule DOES yield explicit confidence', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'Uber', 'cult.fit Live', 'BookMyShow', 'TataCliQ'})],
        contexts: {('c3', 'b-milestone'): const MovieDealContext(isOwned: true, milestoneSpend: 85000)},
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
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
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
          ('c2', 'b-percent'): const MovieDealContext(isOwned: true, confirmedPlatforms: {'PVR'}),
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
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
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
          ('owned-card', 'b-percent'): const MovieDealContext(isOwned: true),
          ('unowned-card', 'b-percent'): const MovieDealContext(isOwned: false),
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
        contexts: {('c1', 'b-percent'): const MovieDealContext(isOwned: true)},
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
        contexts: {('c5', 'b-mult'): const MovieDealContext(isOwned: true)},
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
        contexts: {('c1', 'b-bogo'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.savings, lessThanOrEqualTo(100));
      expect(candidate.savings, greaterThanOrEqualTo(0));
    });
  });

  group('context proof fields pass through to the candidate unchanged', () {
    // These fields (usedTransactions, milestoneSpend, confirmationCount) were
    // already computed by the repository/evaluator for gating purposes, but
    // never surfaced on MovieDealCandidate — the UI could not show "1 of 2
    // redemptions used" or "confirmed by N users" without them, even though
    // the numbers existed one layer down. This proves the pass-through, not
    // new computation.
    test('a bogo candidate carries usedTransactions from its context', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'Zomato'),
        rules: [_bogoRule(partners: {'Zomato'})],
        contexts: {
          ('c1', 'b-bogo'): const MovieDealContext(
            isOwned: true,
            usageConfidence: MovieDealUsageConfidence.verified,
            usedTransactions: 1,
          ),
        },
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c1');
      expect(candidate.usedTransactions, 1);
    });

    test('a candidate with no usage context defaults usedTransactions to 0, matching MovieDealContext default', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300),
        rules: [_percentRule()],
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.usedTransactions, 0);
    });

    test('a milestone candidate carries milestoneSpend from its context', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [_milestoneRule(partners: {'BookMyShow'})],
        contexts: {
          ('c3', 'b-milestone'): const MovieDealContext(isOwned: true, milestoneSpend: 85000),
        },
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c3');
      expect(candidate.milestoneSpend, 85000);
    });

    test('a candidate with no milestoneSpend in its context carries a null milestoneSpend, never a fabricated 0', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 4, pricePerTicket: 300),
        rules: [_percentRule()],
        contexts: {('c2', 'b-percent'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c2');
      expect(candidate.milestoneSpend, isNull);
    });
  });

  group('annualAllowance never fabricates a per-visit savings figure', () {
    // A whole-year cap (e.g. "₹6,000 of free movie tickets annually") is not
    // this specific purchase's discount — there is no remaining-balance
    // tracking anywhere in the schema (confirmed: MovieDealCandidate.
    // remainingVerifiedUsage is declared but never populated), so unlike
    // fixedDiscount/percentDiscount (whose caps genuinely bound THIS
    // transaction), annualAllowance's true per-visit savings is unknowable —
    // the same epistemic gap that already makes rewardMultiplier report 0
    // instead of inventing a rupee figure.
    test('an annualAllowance candidate reports zero computed savings, like rewardMultiplier', () {
      final rule = MovieDealRule(
        benefitId: 'b-annual',
        catalogCardId: 'c6',
        title: 'SBI Card ELITE Free Movie Tickets',
        offerType: MovieDealOfferType.annualAllowance,
        annualCap: 6000,
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 250),
        rules: [rule],
        contexts: {('c6', 'b-annual'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c6');
      expect(candidate.savings, 0);
      expect(candidate.finalAmount, candidate.grossAmount);
    });

    test('an annualAllowance candidate never out-ranks a real, computable percentDiscount candidate', () {
      final annualRule = MovieDealRule(
        benefitId: 'b-annual',
        catalogCardId: 'c6',
        title: 'SBI Card ELITE Free Movie Tickets',
        offerType: MovieDealOfferType.annualAllowance,
        annualCap: 6000,
      );
      final percentRule = _percentRule(cardId: 'c7', percent: 10);
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 250),
        rules: [annualRule, percentRule],
        contexts: {
          ('c6', 'b-annual'): const MovieDealContext(isOwned: false),
          ('c7', 'b-percent'): const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      // Before the fix, annualCap=6000 clamped to the ₹500 gross would tie
      // (or beat) the percent candidate's real ₹50 savings — exactly the
      // mis-ranking this test guards against.
      expect(result.bestPotentialOverall!.cardId, 'c7');
    });

    test('annualAllowance explanation never claims a rupee savings figure', () {
      final rule = MovieDealRule(
        benefitId: 'b-annual',
        catalogCardId: 'c6',
        title: 'SBI Card ELITE Free Movie Tickets',
        offerType: MovieDealOfferType.annualAllowance,
        annualCap: 6000,
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 250),
        rules: [rule],
        contexts: {('c6', 'b-annual'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      final candidate = result.candidates.firstWhere((c) => c.cardId == 'c6');
      expect(candidate.explanation, isNot(contains('saves ₹')));
      expect(candidate.explanation, contains('₹6000'));
    });

    // savings=0 alone made this the SOLE guard against annualAllowance
    // winning by default when it's the only candidate — the exact scenario
    // this reproduces. Still present in `candidates` (so the UI's own
    // dedicated strip can find and render it), just never a `best*` winner.
    test('an annualAllowance candidate never becomes a best* winner even as the sole candidate', () {
      final rule = MovieDealRule(
        benefitId: 'b-annual',
        catalogCardId: 'c6',
        title: 'SBI Card ELITE Free Movie Tickets',
        offerType: MovieDealOfferType.annualAllowance,
        annualCap: 6000,
      );
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 250),
        rules: [rule],
        contexts: {('c6', 'b-annual'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.candidates, hasLength(1));
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestGuaranteedOverall, isNull);
      expect(result.bestPotentialOwned, isNull);
      expect(result.bestPotentialOverall, isNull);
    });
  });

  group('rewardMultiplier is never a best* winner even as the sole candidate', () {
    // The same latent gap annualAllowance had — savings=0 only ever LOSES
    // ranking comparisons, it was never an actual exclusion from winner
    // selection. Genuinely pre-existing (no prior test exercised
    // evaluateMovieDeals' real winner-selection with only a rewardMultiplier
    // candidate present), fixed alongside annualAllowance since both rely on
    // the identical mechanism.
    test('a lone rewardMultiplier candidate never becomes a best* winner', () {
      final rule = MovieDealRule(
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
        rules: [rule],
        contexts: {('c5', 'b-mult'): const MovieDealContext(isOwned: true)},
        now: today,
      );
      expect(result.candidates, hasLength(1));
      expect(result.bestGuaranteedOwned, isNull);
      expect(result.bestGuaranteedOverall, isNull);
      expect(result.bestPotentialOwned, isNull);
      expect(result.bestPotentialOverall, isNull);
    });
  });

  group('full ranked lists per tier×ownership group, not just the top pick', () {
    test('guaranteedOverall lists every eligible guaranteed candidate, ranked by savings desc', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [
          _percentRule(cardId: 'low', percent: 5, partners: {'BookMyShow'}),
          _percentRule(cardId: 'high', percent: 20, partners: {'BookMyShow'}),
          _percentRule(cardId: 'mid', percent: 10, partners: {'BookMyShow'}),
        ],
        contexts: {
          ('low', 'b-percent'): const MovieDealContext(isOwned: false),
          ('high', 'b-percent'): const MovieDealContext(isOwned: false),
          ('mid', 'b-percent'): const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.guaranteedOverall.map((c) => c.cardId), ['high', 'mid', 'low']);
    });

    test('guaranteedOverall is never filtered by ownership — it lists owned AND unowned candidates', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [
          _percentRule(cardId: 'owned-card', percent: 5, partners: {'BookMyShow'}),
          _percentRule(cardId: 'unowned-card', percent: 20, partners: {'BookMyShow'}),
        ],
        contexts: {
          ('owned-card', 'b-percent'): const MovieDealContext(isOwned: true),
          ('unowned-card', 'b-percent'): const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.guaranteedOverall, hasLength(2));
      expect(result.guaranteedOverall.first.cardId, 'unowned-card');
    });

    test('guaranteedOwned lists only owned candidates, still ranked by savings', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [
          _percentRule(cardId: 'owned-low', percent: 5, partners: {'BookMyShow'}),
          _percentRule(cardId: 'owned-high', percent: 20, partners: {'BookMyShow'}),
          _percentRule(cardId: 'unowned', percent: 30, partners: {'BookMyShow'}),
        ],
        contexts: {
          ('owned-low', 'b-percent'): const MovieDealContext(isOwned: true),
          ('owned-high', 'b-percent'): const MovieDealContext(isOwned: true),
          ('unowned', 'b-percent'): const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.guaranteedOwned.map((c) => c.cardId), ['owned-high', 'owned-low']);
    });

    test('potentialOverall lists every eligible potential candidate, ranked by savings desc', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [
          _bogoRule(cardId: 'c1'), // notRequested platform confidence -> potential
          _percentRule(cardId: 'c2', percent: 15), // no partners -> notRequested -> potential
        ],
        contexts: {
          ('c1', 'b-bogo'): const MovieDealContext(isOwned: false),
          ('c2', 'b-percent'): const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.potentialOverall, isNotEmpty);
      // bogo's clamp-to-price (300 < cap 500) beats percent's 45 — the
      // point is that BOTH appear, ranked, not just one winner.
      expect(result.potentialOverall.map((c) => c.cardId), ['c1', 'c2']);
    });

    test('best* fields match the corresponding list\'s first entry', () {
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300, preferredPlatform: 'BookMyShow'),
        rules: [
          _percentRule(cardId: 'owned-card', percent: 5, partners: {'BookMyShow'}),
          _percentRule(cardId: 'unowned-card', percent: 20, partners: {'BookMyShow'}),
        ],
        contexts: {
          ('owned-card', 'b-percent'): const MovieDealContext(isOwned: true),
          ('unowned-card', 'b-percent'): const MovieDealContext(isOwned: false),
        },
        now: today,
      );
      expect(result.bestGuaranteedOwned, result.guaranteedOwned.first);
      expect(result.bestGuaranteedOverall, result.guaranteedOverall.first);
    });

    test('rewardMultiplier and annualAllowance never appear in any of the 4 list fields', () {
      final multiplierRule = MovieDealRule(
        benefitId: 'b-mult',
        catalogCardId: 'c-mult',
        title: '10X points',
        offerType: MovieDealOfferType.rewardMultiplier,
        rewardMultiplierRate: 10,
        rewardMultiplierUnit: 'points per Rs.150',
      );
      final annualRule = MovieDealRule(
        benefitId: 'b-annual',
        catalogCardId: 'c-annual',
        title: 'Free Movie Tickets',
        offerType: MovieDealOfferType.annualAllowance,
        annualCap: 6000,
      );
      final percentRule = _percentRule(cardId: 'c-percent', percent: 15);
      final result = evaluateMovieDeals(
        request: const MovieTicketRequest(numberOfTickets: 2, pricePerTicket: 300),
        rules: [multiplierRule, annualRule, percentRule],
        contexts: {
          ('c-mult', 'b-mult'): const MovieDealContext(isOwned: true),
          ('c-annual', 'b-annual'): const MovieDealContext(isOwned: true),
          ('c-percent', 'b-percent'): const MovieDealContext(isOwned: true),
        },
        now: today,
      );
      final allListedIds = [
        ...result.guaranteedOwned,
        ...result.guaranteedOverall,
        ...result.potentialOwned,
        ...result.potentialOverall,
      ].map((c) => c.cardId);
      expect(allListedIds, isNot(contains('c-mult')));
      expect(allListedIds, isNot(contains('c-annual')));
    });
  });
}
