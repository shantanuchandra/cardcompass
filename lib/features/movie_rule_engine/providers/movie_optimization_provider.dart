import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../data/movie_rule_engine_service.dart';
import '../domain/models/movie_ticket_request.dart';
import '../domain/models/movie_recommendation.dart';

part 'movie_optimization_provider.g.dart';

/// Provider for movie rule engine service
@riverpod
MovieRuleEngineService movieRuleEngineService(Ref ref) {
  return MovieRuleEngineService();
}

/// State provider for movie ticket request
final movieTicketRequestProvider = StateProvider<MovieTicketRequest?>((ref) => null);

/// State provider for current recommendation
final movieRecommendationProvider = StateProvider<MovieRecommendation?>((ref) => null);

/// State provider for optimization process state
final movieOptimizationStateProvider = StateProvider<AsyncValue<MovieRecommendation?>>((ref) {
  return const AsyncValue.data(null);
});

/// Future provider for movie optimization
@riverpod
Future<MovieRecommendation> movieOptimization(Ref ref, (String, MovieTicketRequest) params) async {
  final (userId, request) = params;
  final service = ref.read(movieRuleEngineServiceProvider);
  
  return await service.optimizeMovieTicketPurchase(
    userId: userId,
    request: request,
  );
}

/// Provider for all card-benefit combinations
@riverpod
Future<List<Map<String, dynamic>>> allMovieCardBenefits(Ref ref, String userId) async {
  final service = ref.read(movieRuleEngineServiceProvider);
  return await service.getAllMovieCardBenefits(userId: userId);
}

/// Controller for managing movie optimization state
@riverpod
class MovieOptimizationController extends _$MovieOptimizationController {
  @override
  AsyncValue<MovieRecommendation?> build() {
    return const AsyncValue.data(null);
  }

  /// Optimize movie ticket purchase
  Future<void> optimizeTickets({
    required String userId,
    required MovieTicketRequest request,
  }) async {
    state = const AsyncValue.loading();
    
    try {
      final service = ref.read(movieRuleEngineServiceProvider);
      final recommendation = await service.optimizeMovieTicketPurchase(
        userId: userId,
        request: request,
      );
      
      // Update state providers
      ref.read(movieTicketRequestProvider.notifier).state = request;
      ref.read(movieRecommendationProvider.notifier).state = recommendation;
      
      state = AsyncValue.data(recommendation);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Clear current optimization
  void clearOptimization() {
    ref.read(movieTicketRequestProvider.notifier).state = null;
    ref.read(movieRecommendationProvider.notifier).state = null;
    state = const AsyncValue.data(null);
  }

  /// Retry optimization with current request
  Future<void> retryOptimization(String userId) async {
    final currentRequest = ref.read(movieTicketRequestProvider);
    if (currentRequest != null) {
      await optimizeTickets(userId: userId, request: currentRequest);
    }
  }
}
