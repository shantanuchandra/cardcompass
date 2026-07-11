import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cardcompass/core/services/advanced_benefit_calculation_service.dart';

/// Provider for Advanced Benefit Calculation Service
final advancedBenefitCalculationServiceProvider = Provider<AdvancedBenefitCalculationService>((ref) {
  return AdvancedBenefitCalculationService();
});

/// State class for Enhanced Transaction Advisor
class EnhancedTransactionAdvisorState {
  final bool isLoading;
  final bool isCalculating;
  final Map<String, dynamic>? recommendation;
  final List<Map<String, dynamic>> optimizations;
  final Map<String, dynamic>? rewardSummary;
  final List<Map<String, dynamic>> personalizedRecommendations;
  final String? error;

  const EnhancedTransactionAdvisorState({
    this.isLoading = false,
    this.isCalculating = false,
    this.recommendation,
    this.optimizations = const [],
    this.rewardSummary,
    this.personalizedRecommendations = const [],
    this.error,
  });

  EnhancedTransactionAdvisorState copyWith({
    bool? isLoading,
    bool? isCalculating,
    Map<String, dynamic>? recommendation,
    List<Map<String, dynamic>>? optimizations,
    Map<String, dynamic>? rewardSummary,
    List<Map<String, dynamic>>? personalizedRecommendations,
    String? error,
  }) {
    return EnhancedTransactionAdvisorState(
      isLoading: isLoading ?? this.isLoading,
      isCalculating: isCalculating ?? this.isCalculating,
      recommendation: recommendation ?? this.recommendation,
      optimizations: optimizations ?? this.optimizations,
      rewardSummary: rewardSummary ?? this.rewardSummary,
      personalizedRecommendations: personalizedRecommendations ?? this.personalizedRecommendations,
      error: error,
    );
  }
}

/// ViewModel for Enhanced Transaction Advisor
class EnhancedTransactionAdvisorViewModel extends StateNotifier<EnhancedTransactionAdvisorState> {
  final AdvancedBenefitCalculationService _benefitService;

  EnhancedTransactionAdvisorViewModel(this._benefitService) : super(const EnhancedTransactionAdvisorState());

  /// Calculate best card for transaction
  Future<void> calculateBestCard({
    required String userId,
    required double amount,
    required String merchantName,
    required String category,
    String? mccCode,
  }) async {
    state = state.copyWith(isCalculating: true, error: null);

    try {
      final result = await _benefitService.calculateBestCard(
        userId: userId,
        amount: amount,
        merchantName: merchantName,
        category: category,
        mccCode: mccCode,
      );

      state = state.copyWith(
        isCalculating: false,
        recommendation: result,
      );
    } catch (e) {
      state = state.copyWith(
        isCalculating: false,
        error: e.toString(),
      );
    }
  }

  /// Load spending optimizations
  Future<void> loadOptimizations(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final optimizations = await _benefitService.getSpendingOptimizations(userId);
      state = state.copyWith(
        isLoading: false,
        optimizations: optimizations,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load reward summary
  Future<void> loadRewardSummary(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final summary = await _benefitService.getMonthlyRewardSummary(userId);
      state = state.copyWith(
        isLoading: false,
        rewardSummary: summary,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load personalized recommendations
  Future<void> loadPersonalizedRecommendations(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final recommendations = await _benefitService.getPersonalizedCardRecommendations(userId);
      state = state.copyWith(
        isLoading: false,
        personalizedRecommendations: recommendations,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clear recommendation
  void clearRecommendation() {
    state = state.copyWith(recommendation: null);
  }
}

/// Provider for Enhanced Transaction Advisor ViewModel
final enhancedTransactionAdvisorViewModelProvider = 
    StateNotifierProvider<EnhancedTransactionAdvisorViewModel, EnhancedTransactionAdvisorState>((ref) {
  final benefitService = ref.read(advancedBenefitCalculationServiceProvider);
  return EnhancedTransactionAdvisorViewModel(benefitService);
});
