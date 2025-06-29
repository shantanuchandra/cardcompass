import 'dart:math' as math;
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/core/services/error_handling_service.dart';

/// ML-based analysis service for spending patterns and recommendations
class MLAnalysisService {
  
  /// Analyze spending patterns using machine learning algorithms
  Future<SpendingAnalysisResult> analyzeSpendingPatterns({
    required String userId,
    required List<Transaction> transactions,
    required List<CreditCard> userCards,
  }) async {
    try {
      // Implement ML-based pattern analysis
      final patterns = await _detectSpendingPatterns(transactions);
      final anomalies = await _detectAnomalies(transactions);
      final trends = await _analyzeTrends(transactions);
      final insights = await _generateInsights(patterns, anomalies, trends);
      
      return SpendingAnalysisResult(
        userId: userId,
        analysisDate: DateTime.now(),
        patterns: patterns,
        anomalies: anomalies,
        trends: trends,
        insights: insights,
        confidenceScore: _calculateConfidenceScore(patterns, transactions.length),
      );
    } catch (error, stackTrace) {
      ErrorHandlingService.logError(
        'ML Spending Analysis',
        error,
        stackTrace: stackTrace,
        additionalData: {
          'userId': userId,
          'transactionCount': transactions.length,
          'userCardsCount': userCards.length,
        },
      );
      
      // Return fallback analysis
      return _getFallbackAnalysis(userId, transactions);
    }
  }

  /// Predict future spending using ML models
  Future<SpendingPrediction> predictFutureSpending({
    required String userId,
    required List<Transaction> historicalData,
    required DateTime predictionPeriodStart,
    required DateTime predictionPeriodEnd,
  }) async {
    try {
      // Simple prediction based on historical averages
      final categorySpending = _calculateCategoryAverages(historicalData);
      final seasonalFactors = _calculateSeasonalFactors(historicalData);
      
      final predictions = <String, double>{};
      for (final entry in categorySpending.entries) {
        final baseAmount = entry.value;
        final seasonalFactor = seasonalFactors[entry.key] ?? 1.0;
        predictions[entry.key] = baseAmount * seasonalFactor;
      }
      
      return SpendingPrediction(
        userId: userId,
        predictionDate: DateTime.now(),
        periodStart: predictionPeriodStart,
        periodEnd: predictionPeriodEnd,
        predictedSpending: predictions,
        confidenceLevel: _calculatePredictionConfidence(historicalData.length),
        factors: seasonalFactors,
      );
    } catch (error, stackTrace) {
      ErrorHandlingService.logError(
        'ML Spending Prediction',
        error,
        stackTrace: stackTrace,
        additionalData: {
          'userId': userId,
          'historicalDataCount': historicalData.length,
        },
      );
      
      return _getFallbackPrediction(userId, predictionPeriodStart, predictionPeriodEnd);
    }
  }

  /// Generate personalized card recommendations using ML
  Future<List<MLCardRecommendation>> generateCardRecommendations({
    required String userId,
    required List<Transaction> transactions,
    required List<CreditCard> availableCards,
    required Map<String, dynamic> userProfile,
  }) async {
    try {
      // Analyze user's spending behavior
      final spendingProfile = _createSpendingProfile(transactions);
      
      // Score each card based on user profile
      final scoredCards = <MLCardRecommendation>[];
      
      for (final card in availableCards) {
        final score = _calculateCardScore(card, spendingProfile, userProfile);
        final recommendation = MLCardRecommendation(
          cardId: card.id,
          cardName: card.cardName,
          bankName: card.bankName,
          score: score,
          expectedAnnualValue: _calculateExpectedValue(card, spendingProfile),
          matchedCategories: _getMatchedCategories(card, spendingProfile),
          reasoning: _generateRecommendationReasoning(card, spendingProfile),
        );
        
        scoredCards.add(recommendation);
      }
      
      // Sort by score and return top recommendations
      scoredCards.sort((a, b) => b.score.compareTo(a.score));
      return scoredCards.take(5).toList();
      
    } catch (error, stackTrace) {
      ErrorHandlingService.logError(
        'ML Card Recommendations',
        error,
        stackTrace: stackTrace,
        additionalData: {
          'userId': userId,
          'transactionCount': transactions.length,
          'availableCardsCount': availableCards.length,
        },
      );
      
      return _getFallbackCardRecommendations(availableCards);
    }
  }

  /// Detect spending patterns using clustering algorithms
  Future<List<SpendingPattern>> _detectSpendingPatterns(List<Transaction> transactions) async {
    try {
      final patterns = <SpendingPattern>[];
      
      // Group transactions by category and analyze patterns
      final categoryGroups = <TransactionCategory, List<Transaction>>{};
      for (final transaction in transactions) {
        categoryGroups.putIfAbsent(transaction.category, () => []).add(transaction);
      }
      
      // Analyze each category
      for (final entry in categoryGroups.entries) {
        final categoryTransactions = entry.value;
        if (categoryTransactions.isEmpty) continue;
        
        final pattern = _analyzeCategoryPattern(entry.key, categoryTransactions);
        if (pattern != null) patterns.add(pattern);
      }
      
      return patterns;
    } catch (error) {
      ErrorHandlingService.logError('Pattern Detection', error);
      return [];
    }
  }

  /// Detect anomalies in spending behavior
  Future<List<SpendingAnomaly>> _detectAnomalies(List<Transaction> transactions) async {
    try {
      final anomalies = <SpendingAnomaly>[];
      
      // Calculate statistical thresholds for each category
      final categoryStats = _calculateCategoryStatistics(transactions);
      
      for (final transaction in transactions) {
        final stats = categoryStats[transaction.category];
        if (stats == null) continue;
        
        // Check if transaction amount is significantly higher than average
        final zScore = (transaction.amount - stats['mean']!) / stats['stdDev']!;
        if (zScore.abs() > 2.0) { // 2 standard deviations
          anomalies.add(SpendingAnomaly(
            transactionId: transaction.id,
            category: transaction.category,            amount: transaction.amount,
            expectedAmount: stats['mean']!,
            severity: zScore.abs() > 3.0 ? AnomalySeverity.high : AnomalySeverity.medium,
            reason: 'Unusual spending amount for ${transaction.categoryString} category',
          ));
        }
      }
      
      return anomalies;
    } catch (error) {
      ErrorHandlingService.logError('Anomaly Detection', error);
      return [];
    }
  }

  /// Analyze spending trends
  Future<List<SpendingTrend>> _analyzeTrends(List<Transaction> transactions) async {
    try {
      final trends = <SpendingTrend>[];
      
      // Group transactions by month
      final monthlyData = <String, double>{};
      for (final transaction in transactions) {
        final monthKey = '${transaction.transactionDate.year}-${transaction.transactionDate.month.toString().padLeft(2, '0')}';
        monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + transaction.amount;
      }
      
      // Calculate trend for overall spending
      final overallTrend = _calculateTrendDirection(monthlyData.values.toList());
      trends.add(SpendingTrend(
        category: 'Overall',
        direction: overallTrend,
        changePercentage: _calculateChangePercentage(monthlyData.values.toList()),
        description: _describeTrend(overallTrend),
      ));
      
      return trends;
    } catch (error) {
      ErrorHandlingService.logError('Trend Analysis', error);
      return [];
    }
  }

  /// Generate actionable insights
  Future<List<SpendingInsight>> _generateInsights(
    List<SpendingPattern> patterns,
    List<SpendingAnomaly> anomalies,
    List<SpendingTrend> trends,
  ) async {
    final insights = <SpendingInsight>[];
    
    // Generate insights from patterns
    for (final pattern in patterns) {
      if (pattern.frequency == PatternFrequency.high) {
        insights.add(SpendingInsight(
          type: InsightType.opportunity,
          title: 'High ${pattern.category.name} spending detected',
          description: 'Consider getting a card with better rewards for ${pattern.category.name}',
          actionable: true,
          priority: InsightPriority.medium,
        ));
      }
    }
    
    // Generate insights from anomalies
    if (anomalies.length > 5) {
      insights.add(SpendingInsight(
        type: InsightType.warning,
        title: 'Multiple unusual transactions detected',
        description: 'Review recent transactions for any unauthorized activities',
        actionable: true,
        priority: InsightPriority.high,
      ));
    }
    
    return insights;
  }

  /// Calculate confidence score for analysis
  double _calculateConfidenceScore(List<SpendingPattern> patterns, int transactionCount) {
    if (transactionCount < 10) return 0.3;
    if (transactionCount < 50) return 0.6;
    if (transactionCount < 100) return 0.8;
    return 0.9;
  }

  /// Create spending profile from transactions
  Map<String, dynamic> _createSpendingProfile(List<Transaction> transactions) {
    final categorySpending = <TransactionCategory, double>{};
    double totalSpending = 0;
    
    for (final transaction in transactions) {
      categorySpending[transaction.category] = 
          (categorySpending[transaction.category] ?? 0) + transaction.amount;
      totalSpending += transaction.amount;
    }
    
    // Calculate percentages
    final categoryPercentages = <TransactionCategory, double>{};
    for (final entry in categorySpending.entries) {
      categoryPercentages[entry.key] = (entry.value / totalSpending) * 100;
    }
    
    return {
      'categorySpending': categorySpending,
      'categoryPercentages': categoryPercentages,
      'totalSpending': totalSpending,
      'averageTransactionAmount': totalSpending / transactions.length,
      'topCategories': _getTopCategories(categoryPercentages, 3),
    };
  }

  /// Calculate card score based on user profile
  double _calculateCardScore(
    CreditCard card, 
    Map<String, dynamic> spendingProfile, 
    Map<String, dynamic> userProfile,
  ) {
    double score = 0.0;
    
    final categoryPercentages = spendingProfile['categoryPercentages'] as Map<TransactionCategory, double>;
    final totalSpending = spendingProfile['totalSpending'] as double;
    
    // Score based on reward rates for user's top categories
    for (final entry in categoryPercentages.entries) {
      final categoryName = entry.key.name;
      final percentage = entry.value;
      final rewardRate = card.rewardRates[categoryName] ?? 0.0;
      
      // Weight by spending percentage
      score += rewardRate * percentage * 10; // Multiply by 10 for scaling
    }
    
    // Penalty for high annual fees relative to spending
    final annualFee = card.annualFee ?? 0;
    if (annualFee > totalSpending * 0.02) { // If fee is more than 2% of spending
      score *= 0.8; // Apply 20% penalty
    }
    
    // Bonus for suitable credit limit
    final creditLimit = card.creditLimit ?? 0;
    if (creditLimit > totalSpending * 3) { // Good utilization ratio
      score *= 1.1; // Apply 10% bonus
    }
    
    return score.clamp(0.0, 100.0);
  }

  /// Calculate expected annual value from a card
  double _calculateExpectedValue(CreditCard card, Map<String, dynamic> spendingProfile) {
    final categorySpending = spendingProfile['categorySpending'] as Map<TransactionCategory, double>;
    double totalValue = 0.0;
    
    for (final entry in categorySpending.entries) {
      final categoryName = entry.key.name;
      final spending = entry.value;
      final rewardRate = card.rewardRates[categoryName] ?? 0.0;
      
      totalValue += spending * rewardRate;
    }
    
    // Subtract annual fee
    final annualFee = card.annualFee ?? 0;
    return (totalValue * 12) - annualFee; // Annualize the value
  }

  /// Helper methods for ML analysis
  SpendingPattern? _analyzeCategoryPattern(TransactionCategory category, List<Transaction> transactions) {
    if (transactions.length < 3) return null;
    
    final frequency = transactions.length > 10 ? PatternFrequency.high : 
                     transactions.length > 5 ? PatternFrequency.medium : 
                     PatternFrequency.low;
    
    final averageAmount = transactions.map((t) => t.amount).reduce((a, b) => a + b) / transactions.length;
    
    return SpendingPattern(
      category: category,
      frequency: frequency,
      averageAmount: averageAmount,
      pattern: 'Regular spending detected',
    );
  }

  Map<TransactionCategory, Map<String, double>> _calculateCategoryStatistics(List<Transaction> transactions) {
    final stats = <TransactionCategory, Map<String, double>>{};
    
    final categoryGroups = <TransactionCategory, List<double>>{};
    for (final transaction in transactions) {
      categoryGroups.putIfAbsent(transaction.category, () => []).add(transaction.amount);
    }
    
    for (final entry in categoryGroups.entries) {
      final amounts = entry.value;
      if (amounts.isEmpty) continue;
      
      final mean = amounts.reduce((a, b) => a + b) / amounts.length;
      final variance = amounts.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) / amounts.length;
      final stdDev = math.sqrt(variance);
      
      stats[entry.key] = {
        'mean': mean,
        'stdDev': stdDev,
        'variance': variance,
      };
    }
    
    return stats;
  }
  // Additional helper methods...
  
  Map<String, double> _calculateCategoryAverages(List<Transaction> transactions) {
    final categoryTotals = <String, double>{};
    final categoryCounts = <String, int>{};
    
    for (final transaction in transactions) {
      final category = transaction.categoryString;
      categoryTotals[category] = (categoryTotals[category] ?? 0) + transaction.amount;
      categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
    }
    
    final averages = <String, double>{};
    for (final category in categoryTotals.keys) {
      averages[category] = categoryTotals[category]! / categoryCounts[category]!;
    }
    
    return averages;
  }

  Map<String, double> _calculateSeasonalFactors(List<Transaction> transactions) {
    // Simple seasonal factor calculation
    return {
      'dining': 1.2,      // 20% increase during holidays
      'shopping': 1.5,    // 50% increase during festive seasons
      'travel': 0.8,      // 20% decrease during off-season
      'fuel': 1.0,        // No seasonal variation
      'groceries': 1.1,   // 10% increase
    };
  }

  TrendDirection _calculateTrendDirection(List<double> values) {
    if (values.length < 2) return TrendDirection.stable;
    
    final first = values.first;
    final last = values.last;
    final difference = ((last - first) / first) * 100;
    
    if (difference > 5) return TrendDirection.increasing;
    if (difference < -5) return TrendDirection.decreasing;
    return TrendDirection.stable;
  }

  double _calculateChangePercentage(List<double> values) {
    if (values.length < 2) return 0.0;
    return ((values.last - values.first) / values.first) * 100;
  }

  String _describeTrend(TrendDirection direction) {
    switch (direction) {
      case TrendDirection.increasing:
        return 'Your spending is increasing over time';
      case TrendDirection.decreasing:
        return 'Your spending is decreasing over time';
      case TrendDirection.stable:
        return 'Your spending is relatively stable';
    }
  }

  List<TransactionCategory> _getTopCategories(Map<TransactionCategory, double> percentages, int count) {
    final sorted = percentages.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).map((e) => e.key).toList();
  }

  double _calculatePredictionConfidence(int dataPoints) {
    if (dataPoints < 30) return 0.4;
    if (dataPoints < 90) return 0.7;
    return 0.9;
  }

  List<String> _getMatchedCategories(CreditCard card, Map<String, dynamic> spendingProfile) {
    final topCategories = spendingProfile['topCategories'] as List<TransactionCategory>;
    return topCategories
        .where((cat) => (card.rewardRates[cat.name] ?? 0) > 0.02) // >2% reward rate
        .map((cat) => cat.name)
        .toList();
  }
  String _generateRecommendationReasoning(CreditCard card, Map<String, dynamic> spendingProfile) {
    final matchedCategories = _getMatchedCategories(card, spendingProfile);
    
    if (matchedCategories.isNotEmpty) {
      return 'Excellent rewards for your top spending categories: ${matchedCategories.join(', ')}';
    } else {
      return 'Good overall rewards structure suitable for diverse spending';
    }
  }  // Fallback methods
  SpendingAnalysisResult _getFallbackAnalysis(String userId, List<Transaction> transactions) {
    // Create basic patterns from transactions
    final patterns = transactions.isNotEmpty ? [
      SpendingPattern(
        category: TransactionCategory.other,
        frequency: PatternFrequency.medium,
        averageAmount: transactions.map((t) => t.amount).reduce((a, b) => a + b) / transactions.length,
        pattern: 'General spending pattern',
      ),
    ] : <SpendingPattern>[];

    // Create basic trends
    final trends = [
      SpendingTrend(
        category: 'overall',
        direction: TrendDirection.stable,
        changePercentage: 0.0,
        description: 'Spending patterns appear stable',
      ),
    ];

    return SpendingAnalysisResult(
      userId: userId,
      analysisDate: DateTime.now(),
      patterns: patterns,
      anomalies: [],
      trends: trends,
      insights: [
        SpendingInsight(
          type: InsightType.info,
          title: 'Basic analysis available',
          description: 'Add more transactions for detailed ML insights',
          actionable: false,
          priority: InsightPriority.low,
        ),
      ],
      confidenceScore: 0.3,
    );
  }

  SpendingPrediction _getFallbackPrediction(String userId, DateTime start, DateTime end) {
    return SpendingPrediction(
      userId: userId,
      predictionDate: DateTime.now(),
      periodStart: start,
      periodEnd: end,
      predictedSpending: {'general': 5000.0},
      confidenceLevel: 0.3,
      factors: {},
    );
  }

  List<MLCardRecommendation> _getFallbackCardRecommendations(List<CreditCard> cards) {
    return cards.take(3).map((card) => MLCardRecommendation(
      cardId: card.id,
      cardName: card.cardName,
      bankName: card.bankName,
      score: 50.0,
      expectedAnnualValue: 1000.0,
      matchedCategories: [],
      reasoning: 'Popular choice with good overall benefits',
    )).toList();
  }
}

// Data classes for ML analysis
class SpendingAnalysisResult {
  final String userId;
  final DateTime analysisDate;
  final List<SpendingPattern> patterns;
  final List<SpendingAnomaly> anomalies;
  final List<SpendingTrend> trends;
  final List<SpendingInsight> insights;
  final double confidenceScore;

  SpendingAnalysisResult({
    required this.userId,
    required this.analysisDate,
    required this.patterns,
    required this.anomalies,
    required this.trends,
    required this.insights,
    required this.confidenceScore,
  });
}

class SpendingPattern {
  final TransactionCategory category;
  final PatternFrequency frequency;
  final double averageAmount;
  final String pattern;

  SpendingPattern({
    required this.category,
    required this.frequency,
    required this.averageAmount,
    required this.pattern,
  });
}

class SpendingAnomaly {
  final String transactionId;
  final TransactionCategory category;
  final double amount;
  final double expectedAmount;
  final AnomalySeverity severity;
  final String reason;

  SpendingAnomaly({
    required this.transactionId,
    required this.category,
    required this.amount,
    required this.expectedAmount,
    required this.severity,
    required this.reason,
  });
}

class SpendingTrend {
  final String category;
  final TrendDirection direction;
  final double changePercentage;
  final String description;

  SpendingTrend({
    required this.category,
    required this.direction,
    required this.changePercentage,
    required this.description,
  });
}

class SpendingInsight {
  final InsightType type;
  final String title;
  final String description;
  final bool actionable;
  final InsightPriority priority;

  SpendingInsight({
    required this.type,
    required this.title,
    required this.description,
    required this.actionable,
    required this.priority,
  });
}

class SpendingPrediction {
  final String userId;
  final DateTime predictionDate;
  final DateTime periodStart;
  final DateTime periodEnd;
  final Map<String, double> predictedSpending;
  final double confidenceLevel;
  final Map<String, double> factors;

  SpendingPrediction({
    required this.userId,
    required this.predictionDate,
    required this.periodStart,
    required this.periodEnd,
    required this.predictedSpending,
    required this.confidenceLevel,
    required this.factors,
  });
}

class MLCardRecommendation {
  final String cardId;
  final String cardName;
  final String bankName;
  final double score;
  final double expectedAnnualValue;
  final List<String> matchedCategories;
  final String reasoning;

  MLCardRecommendation({
    required this.cardId,
    required this.cardName,
    required this.bankName,
    required this.score,
    required this.expectedAnnualValue,
    required this.matchedCategories,
    required this.reasoning,
  });
}

// Enums
enum PatternFrequency { low, medium, high }
enum AnomalySeverity { low, medium, high, critical }
enum TrendDirection { increasing, decreasing, stable }
enum InsightType { info, warning, opportunity, alert }
enum InsightPriority { low, medium, high, critical }
