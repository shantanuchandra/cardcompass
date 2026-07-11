import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/features/cards/providers/cards_provider.dart';
import 'package:cardcompass/features/auth/providers/auth_provider.dart';
import 'package:cardcompass/shared/models/benefit.dart';
import 'package:cardcompass/shared/models/benefit_tracking.dart';
import 'package:cardcompass/core/repositories/supabase_benefits_repository.dart';
import 'package:cardcompass/core/repositories/supabase_benefit_tracking_repository.dart';
import 'package:cardcompass/core/mock/mock_data.dart';

/// Repository providers
final supabaseBenefitsRepositoryProvider = Provider<SupabaseBenefitsRepository>((ref) {
  return SupabaseBenefitsRepository();
});

final supabaseBenefitTrackingRepositoryProvider = Provider<SupabaseBenefitTrackingRepository>((ref) {
  return SupabaseBenefitTrackingRepository();
});

/// Provider for benefits view model
final benefitsViewModelProvider = StateNotifierProvider<BenefitsViewModel, BenefitsViewState>((ref) {
  return BenefitsViewModel(ref);
});

/// Benefits view state
class BenefitsViewState {
  final List<CreditCard> userCards;
  final List<BenefitUsage> recentUsage;
  final List<BenefitMetric> metrics;
  final List<BenefitUsageRecord> trackingRecords;
  final BenefitAnalytics? analytics;
  final List<CardBenefit> userCardBenefits;
  final bool isLoading;
  final bool isLoadingTracking;
  final String? error;
  final String selectedCardId;
  final String selectedPeriod;

  const BenefitsViewState({
    this.userCards = const [],
    this.recentUsage = const [],
    this.metrics = const [],
    this.trackingRecords = const [],
    this.analytics,
    this.userCardBenefits = const [],
    this.isLoading = false,
    this.isLoadingTracking = false,
    this.error,
    this.selectedCardId = '',
    this.selectedPeriod = 'month',
  });

  BenefitsViewState copyWith({
    List<CreditCard>? userCards,
    List<BenefitUsage>? recentUsage,
    List<BenefitMetric>? metrics,
    List<BenefitUsageRecord>? trackingRecords,
    BenefitAnalytics? analytics,
    List<CardBenefit>? userCardBenefits,
    bool? isLoading,
    bool? isLoadingTracking,
    String? error,
    String? selectedCardId,
    String? selectedPeriod,
  }) {
    return BenefitsViewState(
      userCards: userCards ?? this.userCards,
      recentUsage: recentUsage ?? this.recentUsage,
      metrics: metrics ?? this.metrics,
      trackingRecords: trackingRecords ?? this.trackingRecords,
      analytics: analytics ?? this.analytics,
      userCardBenefits: userCardBenefits ?? this.userCardBenefits,
      isLoading: isLoading ?? this.isLoading,
      isLoadingTracking: isLoadingTracking ?? this.isLoadingTracking,
      error: error ?? this.error,
      selectedCardId: selectedCardId ?? this.selectedCardId,
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
    );
  }
}

/// Benefits usage tracking
class BenefitUsage {
  final String benefitName;
  final String description;
  final double amountSaved;
  final DateTime usageDate;
  final String cardId;

  const BenefitUsage({
    required this.benefitName,
    required this.description,
    required this.amountSaved,
    required this.usageDate,
    required this.cardId,
  });
}

/// Benefits metrics
class BenefitMetric {
  final String label;
  final String value;
  final String icon;
  final String color;

  const BenefitMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

/// Benefits view model
class BenefitsViewModel extends StateNotifier<BenefitsViewState> {
  final Ref _ref;
  late final SupabaseBenefitsRepository _benefitsRepository;
  late final SupabaseBenefitTrackingRepository _trackingRepository;

  BenefitsViewModel(this._ref) : super(const BenefitsViewState()) {
    _benefitsRepository = _ref.read(supabaseBenefitsRepositoryProvider);
    _trackingRepository = _ref.read(supabaseBenefitTrackingRepositoryProvider);
  }

  /// Load benefits data for user
  Future<void> loadBenefitsData(String userId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Load user cards
      await _loadUserCards(userId);
      
      // Load real benefit data from Supabase
      await _loadUserCardBenefits(userId);
      
      // Load benefit tracking data
      await _loadBenefitTracking(userId);
      
      // Load analytics
      await _loadBenefitAnalytics(userId);
      
      state = state.copyWith(isLoading: false);
    } catch (e) {
      // Fallback to mock data if Supabase fails
      await _loadMockData(userId);
      state = state.copyWith(
        isLoading: false,
        error: 'Using mock data: ${e.toString()}',
      );
    }
  }

  /// Load user cards
  Future<void> _loadUserCards(String userId) async {
    try {
      await _ref.read(cardsProvider.notifier)
          .loadUserCards(userId)
          .timeout(const Duration(seconds: 5));
      final cards = _ref.read(cardsProvider);
      final userCards = cards.where((card) => card.userId.isNotEmpty).toList();
      
      // Use mock cards if no real cards found
      final effectiveCards = userCards.isNotEmpty ? userCards : _getMockCards(userId);
      
      state = state.copyWith(userCards: effectiveCards);
    } catch (e) {
      // Use mock cards on error
      final mockCards = _getMockCards(userId);
      state = state.copyWith(userCards: mockCards);
    }
  }

  /// Load user card benefits from Supabase
  Future<void> _loadUserCardBenefits(String userId) async {
    try {
      final cardBenefits = await _benefitsRepository.getUserCardBenefits(userId);
      state = state.copyWith(userCardBenefits: cardBenefits);
    } catch (e) {
      // Continue with empty benefits if failed
      state = state.copyWith(userCardBenefits: []);
    }
  }

  /// Load benefit tracking data
  Future<void> _loadBenefitTracking(String userId) async {
    state = state.copyWith(isLoadingTracking: true);
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 30));
      
      final trackingRecords = await _trackingRepository.getUserBenefitUsage(
        userId,
        startDate: startDate,
        endDate: now,
        limit: 50,
      );
        final recentUsage = trackingRecords.map((record) => BenefitUsage(
        benefitName: '${record.benefitType} - ${record.category}',
        description: 'Transaction at ${record.merchantName}',
        amountSaved: record.benefitValue,
        usageDate: record.usageDate,
        cardId: record.userCardId,
      )).toList();
      
      state = state.copyWith(
        trackingRecords: trackingRecords,
        recentUsage: recentUsage,
        isLoadingTracking: false,
      );
    } catch (e) {
      // Use mock data on error
      final mockUsage = _generateMockUsageData(state.userCards);
      state = state.copyWith(
        recentUsage: mockUsage,
        isLoadingTracking: false,
      );
    }
  }

  /// Load benefit analytics
  Future<void> _loadBenefitAnalytics(String userId) async {
    try {
      final analytics = await _trackingRepository.getBenefitAnalytics(
        userId,
        period: state.selectedPeriod,
      );
      
      final metrics = _calculateMetricsFromAnalytics(analytics);
      
      state = state.copyWith(
        analytics: analytics,
        metrics: metrics,
      );
    } catch (e) {
      // Use mock metrics on error
      final mockMetrics = _calculateMetrics(state.userCards, state.recentUsage);
      state = state.copyWith(metrics: mockMetrics);
    }
  }

  /// Load mock data as fallback
  Future<void> _loadMockData(String userId) async {
    final mockCards = _getMockCards(userId);
    final mockUsage = _generateMockUsageData(mockCards);
    final mockMetrics = _calculateMetrics(mockCards, mockUsage);
    
    state = state.copyWith(
      userCards: mockCards,
      recentUsage: mockUsage,
      metrics: mockMetrics,
    );
  }

  // Provide mock cards if real load fails or is empty
  List<CreditCard> _getMockCards(String userId) {
    return MockData.creditCards();
  }

  /// Set selected card
  void setSelectedCard(String cardId) {
    state = state.copyWith(selectedCardId: cardId);
  }

  /// Set selected period for analytics and usage tracking
  void setSelectedPeriod(String period) {
    state = state.copyWith(selectedPeriod: period);
    // Reload analytics and tracking data with new period
    final user = _ref.read(authStateProvider).user;
    if (user != null) {
      _loadBenefitAnalytics(user.id);
      _loadBenefitTracking(user.id);
    }
  }

  /// Refresh benefits data
  Future<void> refreshData(String userId) async {
    await loadBenefitsData(userId);
  }

  /// Record a new benefit usage
  Future<void> recordBenefitUsage({
    required String userId,
    required String userCardId,
    required String benefitId,
    required String transactionId,
    required double transactionAmount,
    required double benefitValue,
    required String benefitType,
    required DateTime usageDate,
    required String category,
    required String merchantName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final record = BenefitUsageRecord(
        id: '', // Will be generated by database
        userId: userId,
        userCardId: userCardId,
        benefitId: benefitId,
        transactionId: transactionId,
        transactionAmount: transactionAmount,
        benefitValue: benefitValue,
        benefitType: benefitType,
        usageDate: usageDate,
        category: category,
        merchantName: merchantName,
        metadata: metadata,
        createdAt: DateTime.now(),
      );

      await _trackingRepository.recordBenefitUsage(record);
      
      // Refresh tracking data
      await _loadBenefitTracking(userId);
    } catch (e) {
      state = state.copyWith(error: 'Failed to record benefit usage: $e');
    }
  }

  /// Calculate metrics from analytics data
  List<BenefitMetric> _calculateMetricsFromAnalytics(BenefitAnalytics analytics) {
    return [
      BenefitMetric(
        label: 'Total Benefits Used',
        value: analytics.totalBenefitsUsed.toString(),
        icon: 'check_circle',
        color: 'green',
      ),
      BenefitMetric(
        label: 'Total Savings',
        value: '₹${analytics.totalSavings.toStringAsFixed(0)}',
        icon: 'savings',
        color: 'blue',
      ),
      BenefitMetric(
        label: 'Top Category',
        value: analytics.categoryWiseSavings.isNotEmpty 
            ? analytics.categoryWiseSavings.keys.first
            : 'None',
        icon: 'category',
        color: 'orange',
      ),
      BenefitMetric(
        label: 'Avg Benefit',
        value: analytics.totalBenefitsUsed > 0 
            ? '₹${(analytics.totalSavings / analytics.totalBenefitsUsed).toStringAsFixed(0)}'
            : '₹0',
        icon: 'trending_up',
        color: 'purple',
      ),
    ];
  }

  /// Generate mock usage data, spread across the available cards so
  /// benefit usage doesn't all pile onto a single card.
  List<BenefitUsage> _generateMockUsageData(List<CreditCard> cards) {
    if (cards.isEmpty) return [];

    final cardForIndex = (int i) => cards[i % cards.length].id;

    return [
      BenefitUsage(
        benefitName: 'Dining Cashback',
        description: 'Zomato order',
        amountSaved: 150.0,
        usageDate: DateTime.now().subtract(const Duration(days: 1)),
        cardId: cardForIndex(0),
      ),
      BenefitUsage(
        benefitName: 'Fuel Rewards',
        description: 'Shell petrol station',
        amountSaved: 75.0,
        usageDate: DateTime.now().subtract(const Duration(days: 2)),
        cardId: cardForIndex(1),
      ),
      BenefitUsage(
        benefitName: 'Online Shopping',
        description: 'Amazon purchase',
        amountSaved: 200.0,
        usageDate: DateTime.now().subtract(const Duration(days: 3)),
        cardId: cardForIndex(2),
      ),
    ];
  }

  /// Calculate benefits metrics
  List<BenefitMetric> _calculateMetrics(List<CreditCard> cards, List<BenefitUsage> usage) {
    final activeBenefits = cards.fold<int>(0, (sum, card) => sum + _getActiveBenefitsCount(card));
    final totalSavings = usage.fold<double>(0, (sum, usage) => sum + usage.amountSaved);
    
    return [
      BenefitMetric(
        label: 'Benefits Used',
        value: usage.length.toString(),
        icon: 'check_circle',
        color: 'green',
      ),
      BenefitMetric(
        label: 'Total Savings',
        value: '₹${totalSavings.toStringAsFixed(0)}',
        icon: 'savings',
        color: 'blue',
      ),
      BenefitMetric(
        label: 'Active Benefits',
        value: activeBenefits.toString(),
        icon: 'card_giftcard',
        color: 'orange',
      ),
    ];
  }

  /// Get active benefits count for a card
  int _getActiveBenefitsCount(CreditCard card) {
    return card.benefits.where((b) => b.isActive).length;
  }

  /// Get mock benefits for a card - needed by benefits screen
  List<Map<String, dynamic>> getMockBenefits(CreditCard card) {
    return [
      {
        'category': 'Dining',
        'description': '5% cashback on dining and food delivery',
        'value': '5%',
        'isActive': true,
      },
      {
        'category': 'Fuel',
        'description': 'Fuel surcharge waiver',
        'value': '1%',
        'isActive': true,
      },
      {
        'category': 'Online Shopping',
        'description': '3% cashback on online purchases',
        'value': '3%',
        'isActive': true,
      },
      {
        'category': 'Travel',
        'description': 'Travel insurance and lounge access',
        'value': 'Free',
        'isActive': card.cardName.toLowerCase().contains('premium') || 
                   card.cardName.toLowerCase().contains('platinum'),
      },
      {
        'category': 'Grocery',
        'description': '2% cashback on grocery purchases',
        'value': '2%',
        'isActive': false,
      },
    ];
  }

  /// Get benefits for selected cards
  List<CreditCard> getSelectedCards() {
    if (state.selectedCardId.isEmpty) {
      return state.userCards;
    }
    return state.userCards.where((card) => card.id == state.selectedCardId).toList();
  }
  /// Get card benefits for display
  List<CardBenefit> getCardBenefits(String cardId) {
    return state.userCardBenefits.where((cb) => cb.cardId == cardId).toList();
  }

  /// Get spending insights for a category
  Future<Map<String, dynamic>> getCategoryInsights(String userId, String category) async {
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 90));
      
      final records = await _trackingRepository.getUserBenefitUsage(
        userId,
        startDate: startDate,
        endDate: now,
        category: category,
      );

      final totalSpent = records.fold<double>(0, (sum, record) => sum + record.transactionAmount);
      final totalSaved = records.fold<double>(0, (sum, record) => sum + record.benefitValue);
      final savingsRate = totalSpent > 0 ? (totalSaved / totalSpent) * 100 : 0;

      return {
        'total_spent': totalSpent,
        'total_saved': totalSaved,
        'savings_rate': savingsRate,
        'transaction_count': records.length,
        'avg_transaction': records.isNotEmpty ? totalSpent / records.length : 0,
      };
    } catch (e) {
      throw Exception('Failed to get category insights: $e');
    }
  }
}
