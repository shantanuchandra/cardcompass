import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/movie_rule_engine_service.dart';
import '../domain/models/movie_ticket_request.dart';
import '../domain/models/movie_recommendation.dart';

/// Provider for movie rule engine service
final movieRuleEngineServiceProvider = Provider<MovieRuleEngineService>((ref) {
  return MovieRuleEngineService();
});

/// State provider for movie ticket request
final movieTicketRequestProvider = StateProvider<MovieTicketRequest?>((ref) => null);

/// State provider for current recommendation
final movieRecommendationProvider = StateProvider<MovieRecommendation?>((ref) => null);

/// Provider for optimization process state
final movieOptimizationStateProvider = StateProvider<AsyncValue<MovieRecommendation?>>((ref) {
  return const AsyncValue.data(null);
});

/// Future provider for movie optimization
final movieOptimizationProvider = FutureProvider.family<MovieRecommendation, (String, MovieTicketRequest)>((ref, params) async {
  final (userId, request) = params;
  final service = ref.read(movieRuleEngineServiceProvider);
  
  return await service.optimizeMovieTicketPurchase(
    userId: userId,
    request: request,
  );
});

/// Provider for optimization with loading state management
final movieOptimizationControllerProvider = StateNotifierProvider<MovieOptimizationController, AsyncValue<MovieRecommendation?>>((ref) {
  return MovieOptimizationController(ref);
});

/// Controller for managing movie optimization state
class MovieOptimizationController extends StateNotifier<AsyncValue<MovieRecommendation?>> {
  final Ref _ref;

  MovieOptimizationController(this._ref) : super(const AsyncValue.data(null));

  /// Optimize movie ticket purchase
  Future<void> optimizeTickets({
    required String userId,
    required MovieTicketRequest request,
  }) async {
    state = const AsyncValue.loading();
    
    try {
      final service = _ref.read(movieRuleEngineServiceProvider);
      final recommendation = await service.optimizeMovieTicketPurchase(
        userId: userId,
        request: request,
      );
      
      // Update state providers
      _ref.read(movieTicketRequestProvider.notifier).state = request;
      _ref.read(movieRecommendationProvider.notifier).state = recommendation;
      
      state = AsyncValue.data(recommendation);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Clear current optimization
  void clearOptimization() {
    _ref.read(movieTicketRequestProvider.notifier).state = null;
    _ref.read(movieRecommendationProvider.notifier).state = null;
    state = const AsyncValue.data(null);
  }

  /// Retry optimization with current request
  Future<void> retryOptimization(String userId) async {
    final currentRequest = _ref.read(movieTicketRequestProvider);
    if (currentRequest != null) {
      await optimizeTickets(userId: userId, request: currentRequest);
    }
  }
}
