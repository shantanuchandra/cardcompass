import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/providers/service_providers.dart';

part 'recommendations_viewmodel.g.dart';

/// Card recommendation model
@immutable
class CardRecommendation {
  final CreditCard card;
  final double potentialAnnualSavings;
  final String reasonCode;
  final double confidenceScore;
  final List<String> benefits;

  const CardRecommendation({
    required this.card,
    required this.potentialAnnualSavings,
    required this.reasonCode,
    required this.confidenceScore,
    required this.benefits,
  });
}

/// Recommendations view state
@immutable
class RecommendationsViewState {
  final bool isLoading;
  final String? error;
  final List<CardRecommendation> recommendations;
  final DateTime? lastUpdated;

  const RecommendationsViewState({
    this.isLoading = false,
    this.error,
    this.recommendations = const [],
    this.lastUpdated,
  });

  RecommendationsViewState copyWith({
    bool? isLoading,
    String? error,
    List<CardRecommendation>? recommendations,
    DateTime? lastUpdated,
  }) {
    return RecommendationsViewState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      recommendations: recommendations ?? this.recommendations,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

@riverpod
class RecommendationsViewModel extends _$RecommendationsViewModel {
  late final RecommendationService _recommendationService;

  @override
  RecommendationsViewState build() {
    _recommendationService = ref.watch(recommendationServiceProvider);
    return const RecommendationsViewState();
  }

  /// Load personalized card recommendations
  Future<void> loadRecommendations(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Get recommendations from service
      final recommendations = await _recommendationService.getCardRecommendations(
        userId: userId,
        limit: 5,
      );

      // Convert to UI model
      final cardRecommendations = recommendations.map((rec) {
        return CardRecommendation(
          card: rec,
          potentialAnnualSavings: 5000.0, // Placeholder
          reasonCode: 'best_fit',
          confidenceScore: 0.85,
          benefits: _extractCardBenefits(rec),
        );
      }).toList();

      state = state.copyWith(
        isLoading: false,
        recommendations: cardRecommendations,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  /// Extract key benefits from card
  List<String> _extractCardBenefits(CreditCard card) {
    final benefits = <String>[];
    
    // Extract benefits from card rewards and features
    if (card.rewardRates.isNotEmpty) {
      benefits.add('Reward Points');
    }
    
    // Add some common benefits
    benefits.add('Cashback Rewards');
    benefits.add('Travel Benefits');

    // Add some default benefits based on card type
    if (card.type == CardType.credit && (card.annualFee ?? 0) > 5000) {
      benefits.add('Premium Lounge Access');
    }

    return benefits.take(3).toList(); // Limit to 3 key benefits
  }

  /// Refresh recommendations
  Future<void> refreshRecommendations(String userId) async {
    await loadRecommendations(userId);
  }
}


