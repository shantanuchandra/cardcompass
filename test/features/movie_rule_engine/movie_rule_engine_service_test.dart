import 'package:cardcompass/features/movie_rule_engine/data/movie_deals_repository.dart';
import 'package:cardcompass/features/movie_rule_engine/data/movie_rule_engine_service.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_candidate.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_deal_rule.dart';
import 'package:cardcompass/features/movie_rule_engine/domain/models/movie_ticket_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MovieTicketRequest request(int tickets, double price) => MovieTicketRequest(
        numberOfTickets: tickets,
        pricePerTicket: price,
      );

  test('returns unavailable rather than no deals when repository fails',
      () async {
    final service = MovieRuleEngineService(_ThrowingRepository());

    final result = await service.optimizeMovieDeals(
      userId: 'u',
      request: request(2, 300),
    );

    expect(result.status, MovieDealsStatus.unavailable);
    expect(result.candidates, isEmpty);
  });

  test('returns owned and overall evaluated deals from one repository snapshot',
      () async {
    final service = MovieRuleEngineService(_SnapshotRepository(
      MovieDealsSnapshot(
        sources: [
          _source('owned', 'owned-benefit', 20),
          _source('other', 'other-benefit', 30)
        ],
        contexts: const {
          'owned': MovieDealContext(isOwned: true),
          'other': MovieDealContext(),
        },
      ),
    ));

    final result = await service.optimizeMovieDeals(
      userId: 'u',
      request: request(2, 300),
    );

    expect(result.status, MovieDealsStatus.available);
    expect(result.bestOwned?.cardId, 'owned');
    expect(result.bestOverall?.cardId, 'other');
  });

  test('retains diagnostics for rejected normalized rules', () async {
    final service = MovieRuleEngineService(_SnapshotRepository(
      MovieDealsSnapshot(
        sources: [_source('bad', 'bad-benefit', 0)],
        contexts: const {},
      ),
    ));

    final result = await service.optimizeMovieDeals(
      userId: 'u',
      request: request(2, 300),
    );

    expect(result.status, MovieDealsStatus.available);
    expect(result.candidates, isEmpty);
    expect(result.rejectedCandidates, hasLength(1));
    expect(result.rejectedCandidates.single.benefitId, 'bad-benefit');
    expect(result.rejectedCandidates.single.reason, isNotEmpty);
  });
}

MovieBenefitSource _source(
        String cardId, String benefitId, double percentage) =>
    MovieBenefitSource(
      benefitId: benefitId,
      catalogCardId: cardId,
      title: 'Offer $benefitId',
      valueConfig: {
        'offer_type': 'PERCENT_DISCOUNT',
        'discount_percent': percentage,
      },
    );

class _SnapshotRepository implements MovieDealsRepository {
  _SnapshotRepository(this.snapshot);

  final MovieDealsSnapshot snapshot;

  @override
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  ) async =>
      snapshot;
}

class _ThrowingRepository implements MovieDealsRepository {
  @override
  Future<MovieDealsSnapshot> loadSnapshot(
    String userId,
    MovieTicketRequest request,
  ) =>
      throw StateError('database unavailable');
}
