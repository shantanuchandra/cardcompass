import 'package:flutter_riverpod/legacy.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/providers/service_providers.dart';

class TransactionRecommendation {
  final CreditCard? bestUserCard;
  final CreditCard? bestOverallCard;
  final double bestUserReward;
  final double bestOverallReward;
  final double potentialSavings;
  final String recommendationReason;

  const TransactionRecommendation({
    this.bestUserCard,
    this.bestOverallCard,
    this.bestUserReward = 0.0,
    this.bestOverallReward = 0.0,
    this.potentialSavings = 0.0,
    this.recommendationReason = '',
  });
}

class TransactionAdvisorViewState {
  final List<CreditCard> userCards;
  final List<CreditCard> allCards;
  final bool isLoading;
  final bool isCalculating;
  final String? error;
  final TransactionRecommendation? currentRecommendation;

  const TransactionAdvisorViewState({
    this.userCards = const [],
    this.allCards = const [],
    this.isLoading = false,
    this.isCalculating = false,
    this.error,
    this.currentRecommendation,
  });

  TransactionAdvisorViewState copyWith({
    List<CreditCard>? userCards,
    List<CreditCard>? allCards,
    bool? isLoading,
    bool? isCalculating,
    String? error,
    TransactionRecommendation? currentRecommendation,
  }) {
    return TransactionAdvisorViewState(
      userCards: userCards ?? this.userCards,
      allCards: allCards ?? this.allCards,
      isLoading: isLoading ?? this.isLoading,
      isCalculating: isCalculating ?? this.isCalculating,
      error: error,
      currentRecommendation: currentRecommendation ?? this.currentRecommendation,
    );
  }

  bool get hasRecommendation => currentRecommendation != null;
  bool get canCalculate => userCards.isNotEmpty;
}

class TransactionAdvisorViewModel extends StateNotifier<TransactionAdvisorViewState> {
  final RecommendationService _recommendationService;

  TransactionAdvisorViewModel(
    this._recommendationService,
  ) : super(const TransactionAdvisorViewState());
  Future<void> initialize(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // For now, we'll use mock data or get from other sources
      // This would typically come from a repository
      final userCards = <CreditCard>[];
      final allCards = <CreditCard>[];

      state = state.copyWith(
        userCards: userCards,
        allCards: allCards,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isLoading: false,
      );
    }
  }

  Future<void> getRecommendation({
    required String merchantName,
    required String category,
    required double amount,
  }) async {
    state = state.copyWith(isCalculating: true, error: null);

    try {
      // Calculate best user card
      CreditCard? bestUserCard;
      double bestUserReward = 0.0;

      for (final card in state.userCards) {
        final reward = await _recommendationService.calculateReward(
          card: card,
          merchantName: merchantName,
          category: category,
          amount: amount,
        );

        if (reward > bestUserReward) {
          bestUserReward = reward;
          bestUserCard = card;
        }
      }

      // Calculate best overall card
      CreditCard? bestOverallCard;
      double bestOverallReward = 0.0;

      for (final card in state.allCards) {
        final reward = await _recommendationService.calculateReward(
          card: card,
          merchantName: merchantName,
          category: category,
          amount: amount,
        );

        if (reward > bestOverallReward) {
          bestOverallReward = reward;
          bestOverallCard = card;
        }
      }

      // Calculate potential savings
      final potentialSavings = bestOverallReward - bestUserReward;

      final recommendation = TransactionRecommendation(
        bestUserCard: bestUserCard,
        bestOverallCard: bestOverallCard,
        bestUserReward: bestUserReward,
        bestOverallReward: bestOverallReward,
        potentialSavings: potentialSavings > 0 ? potentialSavings : 0.0,
        recommendationReason: _generateRecommendationReason(
          bestUserCard,
          bestOverallCard,
          potentialSavings,
        ),
      );

      state = state.copyWith(
        currentRecommendation: recommendation,
        isCalculating: false,
      );
    } catch (error) {
      state = state.copyWith(
        error: error.toString(),
        isCalculating: false,
      );
    }
  }

  void clearRecommendation() {
    state = state.copyWith(currentRecommendation: null);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  String _generateRecommendationReason(
    CreditCard? bestUserCard,
    CreditCard? bestOverallCard,
    double potentialSavings,
  ) {
    if (bestUserCard == null) {
      return 'No cards available for calculation';
    }

    if (potentialSavings > 0 && bestOverallCard != null) {
      return 'Consider applying for ${bestOverallCard.cardName} to earn ₹${potentialSavings.toStringAsFixed(2)} more rewards';
    }

    return 'Using ${bestUserCard.cardName} gives you the best reward for this transaction';
  }
}

// Provider for TransactionAdvisorViewModel
final transactionAdvisorViewModelProvider = 
    StateNotifierProvider<TransactionAdvisorViewModel, TransactionAdvisorViewState>((ref) {
  final recommendationService = ref.watch(recommendationServiceProvider);
  return TransactionAdvisorViewModel(recommendationService);
});
