import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/core/services/recommendation_service.dart';
import 'package:cardcompass/core/providers/service_providers.dart';
import 'package:cardcompass/core/repositories/supabase_card_repository.dart';
import 'package:cardcompass/core/repositories/supabase_transaction_repository.dart';

part 'dashboard_viewmodel.g.dart';

/// State class for dashboard view
class DashboardViewState {
  final bool isLoading;
  final String? error;
  final List<Transaction> recentTransactions;
  final List<CreditCard> userCards;
  final Map<String, double> monthlyTrend;
  final double totalMonthlySpending;
  final double totalMonthlyRewards;
  final Map<String, double> categoryBreakdown;
  
  // AI-powered insights and recommendations
  final List<SpendingOptimization> spendingOptimizations;
  final List<CreditCard> aiCardRecommendations;
  final SpendingAnalysis? spendingAnalysis;
  final List<String> aiInsights;
  DashboardViewState({
    this.isLoading = false,
    this.error,
    this.recentTransactions = const [],
    this.userCards = const [],
    this.monthlyTrend = const {},
    this.totalMonthlySpending = 0.0,
    this.totalMonthlyRewards = 0.0,
    this.categoryBreakdown = const {},
    this.spendingOptimizations = const [],
    this.aiCardRecommendations = const [],
    this.spendingAnalysis,
    this.aiInsights = const [],
  });
  DashboardViewState copyWith({
    bool? isLoading,
    String? error,
    List<Transaction>? recentTransactions,
    List<CreditCard>? userCards,
    Map<String, double>? monthlyTrend,
    double? totalMonthlySpending,
    double? totalMonthlyRewards,
    Map<String, double>? categoryBreakdown,
    List<SpendingOptimization>? spendingOptimizations,
    List<CreditCard>? aiCardRecommendations,
    SpendingAnalysis? spendingAnalysis,
    List<String>? aiInsights,
  }) {
    return DashboardViewState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      userCards: userCards ?? this.userCards,
      monthlyTrend: monthlyTrend ?? this.monthlyTrend,
      totalMonthlySpending: totalMonthlySpending ?? this.totalMonthlySpending,
      totalMonthlyRewards: totalMonthlyRewards ?? this.totalMonthlyRewards,
      categoryBreakdown: categoryBreakdown ?? this.categoryBreakdown,
      spendingOptimizations: spendingOptimizations ?? this.spendingOptimizations,
      aiCardRecommendations: aiCardRecommendations ?? this.aiCardRecommendations,
      spendingAnalysis: spendingAnalysis ?? this.spendingAnalysis,
      aiInsights: aiInsights ?? this.aiInsights,
    );
  }
}

@riverpod
class DashboardViewModel extends _$DashboardViewModel {
  late final RecommendationService _recommendationService;

  @override
  DashboardViewState build() {
    _recommendationService = ref.watch(recommendationServiceProvider);
    return DashboardViewState();
  }

  /// Load dashboard data for user
  Future<void> loadDashboardData(String userId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Fetch real data from repositories
      final transactionRepository = SupabaseTransactionRepository();
      final cardRepository = SupabaseCardRepository();
      
      final recentTransactions = await transactionRepository.getUserTransactions(userId, limit: 20);
      final userCards = await cardRepository.getUserCards(userId);
      
      // Calculate monthly trend from real data
      final monthlyTrend = _calculateMonthlyTrend(recentTransactions);
      final categoryBreakdown = _calculateCategoryBreakdown(recentTransactions);
      
      // Calculate totals
      final totalMonthlySpending = recentTransactions
          .where((t) => _isCurrentMonth(t.transactionDate))
          .fold(0.0, (sum, t) => sum + t.amount);      final totalMonthlyRewards = recentTransactions
          .where((t) => _isCurrentMonth(t.transactionDate))
          .fold(0.0, (sum, t) => sum + (t.rewardEarned ?? 0.0));

      // Get AI-powered recommendations and insights
      final aiCardRecommendations = await _recommendationService.getCardRecommendations(
        userId: userId, 
        limit: 3
      );
      
      final spendingOptimizations = await _recommendationService.getSpendingOptimizations(
        userId: userId
      );
      
      final spendingAnalysis = await _recommendationService.analyzeSpendingPatterns(
        userId: userId
      );

      state = state.copyWith(
        isLoading: false,
        recentTransactions: recentTransactions,
        userCards: userCards,
        monthlyTrend: monthlyTrend,
        totalMonthlySpending: totalMonthlySpending,
        totalMonthlyRewards: totalMonthlyRewards,
        categoryBreakdown: categoryBreakdown,
        aiCardRecommendations: aiCardRecommendations,
        spendingOptimizations: spendingOptimizations,
        spendingAnalysis: spendingAnalysis,
        aiInsights: spendingAnalysis.insights,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load dashboard data: ${e.toString()}',
      );
    }
  }

  /// Refresh dashboard data
  Future<void> refreshData(String userId) async {
    await loadDashboardData(userId);
  }
  /// Check if transaction is from current month
  bool _isCurrentMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  /// Calculate monthly spending trend from transactions
  Map<String, double> _calculateMonthlyTrend(List<Transaction> transactions) {
    final Map<String, double> monthlyTotals = {};
    
    for (final transaction in transactions) {
      final monthKey = '${transaction.transactionDate.year}-${transaction.transactionDate.month.toString().padLeft(2, '0')}';
      monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0.0) + transaction.amount.abs();
    }
    
    return monthlyTotals;
  }
  /// Calculate category breakdown from transactions
  Map<String, double> _calculateCategoryBreakdown(List<Transaction> transactions) {
    final Map<String, double> categoryTotals = {};
    
    for (final transaction in transactions) {
      final category = transaction.categoryString;
      categoryTotals[category] = (categoryTotals[category] ?? 0.0) + transaction.amount.abs();
    }
    
    return categoryTotals;
  }

  /// Get total monthly spending
  double get totalMonthlySpending => state.totalMonthlySpending;

  /// Get total monthly rewards
  double get totalMonthlyRewards => state.totalMonthlyRewards;
}


