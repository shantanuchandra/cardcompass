// lib/features/benefits/movie_deals/providers/movie_deals_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/services/parsing_logger.dart';
import '../domain/movie_deal_evaluator.dart';
import '../domain/movie_deal_rule.dart';
import '../domain/movie_deal_rule_normalizer.dart';
import '../domain/movie_ticket_request.dart';

const _unavailableRecommendation = MovieDealsRecommendation(
  candidates: [],
  rejectedCandidates: [],
  status: MovieDealsStatus.unavailable,
);

/// Runs one Movie Deals search: loads a snapshot keyed by
/// (catalogCardId, benefitId), normalizes every source, evaluates accepted
/// rules, and returns a guaranteed/potential-tiered recommendation.
/// Returns MovieDealsStatus.unavailable rather than an empty no-deal
/// result on any failure (design spec §11).
final movieDealsSearchProvider =
    FutureProvider.family<MovieDealsRecommendation, MovieTicketRequest>(
        (ref, request) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return _unavailableRecommendation;
  }

  try {
    // Computed once and reused for both calls below — movie_deals_repository.dart's
    // loadSnapshot() and evaluateMovieDeals() both gate time-sensitive logic
    // (milestone cycle-completion, rule validity dates) on `now`; calling
    // DateTime.now() separately at each call site risks the two moments
    // straddling a boundary (e.g. midnight) and disagreeing about which
    // cycle is "current" within the same single search.
    final now = DateTime.now();
    final repository = ref.read(movieDealsRepositoryProvider);
    final snapshot = await repository.loadSnapshot(user.id, request, now: now);

    final rules = <MovieDealRule>[];
    for (final source in snapshot.sources) {
      final normalized = normalizeMovieDealRule(source);
      if (normalized case AcceptedMovieDealRule(:final rule)) {
        rules.add(rule);
      }
    }

    return evaluateMovieDeals(
      request: request,
      rules: rules,
      contexts: snapshot.contexts,
      now: now,
    );
  } catch (e) {
    ParsingLogger.error('movieDealsSearchProvider: search failed', e);
    return _unavailableRecommendation;
  }
});
