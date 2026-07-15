import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models/movie_deal_candidate.dart';
import '../domain/models/movie_deal_rule.dart';
import '../domain/models/movie_recommendation.dart';
import '../domain/models/movie_ticket_request.dart';
import '../domain/models/transaction_step.dart';
import '../domain/movie_deal_evaluator.dart';
import '../domain/movie_deal_rule_normalizer.dart';
import 'movie_deals_repository.dart';

/// Loads one read-only snapshot and coordinates normalization and evaluation.
///
/// This service deliberately owns no database writes or usage-cache updates.
class MovieRuleEngineService {
  MovieRuleEngineService([MovieDealsRepository? repository])
      : _repository = repository ??
            MovieDealsSupabaseRepository(
              SupabaseMovieDealsDataSource(Supabase.instance.client),
            );

  final MovieDealsRepository _repository;

  Future<MovieDealsRecommendation> optimizeMovieDeals({
    required String userId,
    required MovieTicketRequest request,
  }) async {
    try {
      final snapshot = await _repository.loadSnapshot(userId, request);
      final rules = <MovieDealRule>[];
      final rejected = <RejectedMovieDealCandidate>[];

      for (final source in snapshot.sources) {
        final normalized = normalizeMovieDealRule(source);
        switch (normalized) {
          case AcceptedMovieDealRule(:final rule):
            rules.add(rule);
          case RejectedMovieDealRule(:final reason):
            rejected.add(RejectedMovieDealCandidate(
              cardId: source.catalogCardId,
              benefitId: source.benefitId,
              rule: _diagnosticRule(source),
              reason: reason,
            ));
        }
      }

      final evaluated = evaluateMovieDeals(
        request: request,
        rules: rules,
        contexts: snapshot.contexts,
        now: DateTime.now(),
      );
      return MovieDealsRecommendation(
        candidates: evaluated.candidates,
        rejectedCandidates: [...rejected, ...evaluated.rejectedCandidates],
        bestOwned: evaluated.bestOwned,
        bestOverall: evaluated.bestOverall,
      );
    } catch (_) {
      return MovieDealsRecommendation(
        candidates: const [],
        rejectedCandidates: const [],
        status: MovieDealsStatus.unavailable,
      );
    }
  }

  /// Compatibility adapter for the existing presentation layer.
  Future<MovieRecommendation> optimizeMovieTicketPurchase({
    required String userId,
    required MovieTicketRequest request,
  }) async {
    final deals = await optimizeMovieDeals(userId: userId, request: request);
    final best = deals.bestOverall;
    if (deals.status == MovieDealsStatus.unavailable || best == null) {
      return MovieRecommendation.empty(
        totalAmount: request.totalAmount,
        tickets: request.numberOfTickets,
      );
    }
    return MovieRecommendation(
      steps: [
        TransactionStep(
          platform: request.preferredPlatform ?? 'All platforms',
          cardName: best.rule.cardName ?? best.title,
          cardId: best.cardId,
          ticketCount: request.numberOfTickets,
          amount: best.grossAmount,
          savings: best.savings,
          benefitType: best.rule.offerType.name.toUpperCase(),
          explanation: best.explanation,
          benefitDetails: {'is_owned': best.isOwned},
        ),
      ],
      totalAmount: best.grossAmount,
      totalSavings: best.savings,
      finalAmount: best.finalAmount,
      explanation: best.explanation,
      calculatedAt: DateTime.now(),
    );
  }

  /// Compatibility adapter for the existing display provider.
  Future<List<Map<String, dynamic>>> getAllMovieCardBenefits({
    required String userId,
  }) async {
    final request = MovieTicketRequest(numberOfTickets: 1, pricePerTicket: 1);
    try {
      final snapshot = await _repository.loadSnapshot(userId, request);
      return snapshot.sources.map((source) {
        final context = snapshot.contexts[source.catalogCardId];
        return {
          'card_id': source.catalogCardId,
          'card_name': source.cardName,
          'benefit_title': source.title,
          'is_owned': context?.isOwned ?? false,
        };
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

/// Gives malformed rules a stable identity for diagnostics without inventing
/// commercial terms that the normalizer rejected.
MovieDealRule _diagnosticRule(MovieBenefitSource source) => MovieDealRule(
      benefitId: source.benefitId,
      catalogCardId: source.catalogCardId,
      title: source.title,
      offerType: MovieDealOfferType.fixedDiscount,
      sourceUrl: source.sourceUrl,
      cardName: source.cardName,
      displayPriority: source.displayPriority,
    );
