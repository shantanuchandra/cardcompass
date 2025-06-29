import 'dart:math';
import 'package:cardcompass/shared/models/transaction.dart';
import 'package:cardcompass/shared/models/credit_card.dart';

/// Enhanced analytics service for advanced financial insights
class EnhancedAnalyticsService {
  /// Generate comprehensive financial insights for a user
  Future<FinancialInsights> generateComprehensiveInsights({
    required String userId,
    required List<Transaction> transactions,
    required List<CreditCard> creditCards,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final filteredTransactions = _filterTransactionsByDate(
      transactions, 
      startDate ?? DateTime.now().subtract(const Duration(days: 365)),
      endDate ?? DateTime.now(),
    );
    
    return FinancialInsights(
      spendingTrends: await _analyzeSpendingTrends(filteredTransactions),
      categoryInsights: await _analyzeCategorySpending(filteredTransactions),
      cardUtilization: await _analyzeCardUtilization(filteredTransactions, creditCards),
      savingsOpportunities: await _identifySavingsOpportunities(filteredTransactions),
      rewardOptimization: await _analyzeRewardOptimization(filteredTransactions, creditCards),
      budgetRecommendations: await _generateBudgetRecommendations(filteredTransactions),
      financialHealthScore: await _calculateFinancialHealthScore(filteredTransactions, creditCards),
      predictiveInsights: await _generatePredictiveInsights(filteredTransactions),
    );
  }
  
  /// Analyze spending trends over time
  Future<SpendingTrendAnalysis> _analyzeSpendingTrends(List<Transaction> transactions) async {
    final monthlyData = <String, double>{};
    final weeklyData = <String, double>{};
    final dailyData = <String, double>{};
    
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        final amount = transaction.amount.abs();
        
        // Monthly aggregation
        final monthKey = '${transaction.transactionDate.year}-${transaction.transactionDate.month.toString().padLeft(2, '0')}';
        monthlyData[monthKey] = (monthlyData[monthKey] ?? 0) + amount;
        
        // Weekly aggregation
        final weekStart = _getWeekStart(transaction.transactionDate);
        final weekKey = '${weekStart.day}/${weekStart.month}';
        weeklyData[weekKey] = (weeklyData[weekKey] ?? 0) + amount;
        
        // Daily aggregation
        final dayKey = '${transaction.transactionDate.day}/${transaction.transactionDate.month}';
        dailyData[dayKey] = (dailyData[dayKey] ?? 0) + amount;
      }
    }
    
    return SpendingTrendAnalysis(
      monthlySpending: monthlyData,
      weeklySpending: weeklyData,
      dailySpending: dailyData,
      trendDirection: _calculateTrendDirection(monthlyData),
      averageMonthlySpending: _calculateAverage(monthlyData.values.toList()),
      spendingVolatility: _calculateVolatility(monthlyData.values.toList()),
    );
  }
  
  /// Analyze spending by category with insights
  Future<CategoryInsightsAnalysis> _analyzeCategorySpending(List<Transaction> transactions) async {
    final categoryTotals = <TransactionCategory, double>{};
    final categoryTransactionCounts = <TransactionCategory, int>{};
    final categoryMonthlyTrends = <TransactionCategory, Map<String, double>>{};
    
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        final amount = transaction.amount.abs();
        final category = transaction.category;
        
        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
        categoryTransactionCounts[category] = (categoryTransactionCounts[category] ?? 0) + 1;
        
        // Monthly trend for this category
        final monthKey = '${transaction.transactionDate.year}-${transaction.transactionDate.month.toString().padLeft(2, '0')}';
        categoryMonthlyTrends[category] ??= <String, double>{};
        categoryMonthlyTrends[category]![monthKey] = (categoryMonthlyTrends[category]![monthKey] ?? 0) + amount;
      }
    }
    
    final totalSpending = categoryTotals.values.fold(0.0, (a, b) => a + b);
    final insights = <CategoryInsight>[];
    
    for (final entry in categoryTotals.entries) {
      final category = entry.key;
      final amount = entry.value;
      final percentage = totalSpending > 0 ? (amount / totalSpending) * 100 : 0;
        insights.add(CategoryInsight(
        category: category,
        totalSpent: amount,
        percentage: percentage.toDouble(),
        transactionCount: categoryTransactionCounts[category] ?? 0,
        averageTransactionAmount: amount / (categoryTransactionCounts[category] ?? 1),
        monthlyTrend: categoryMonthlyTrends[category] ?? {},
        insight: _generateCategoryInsight(category, percentage.toDouble(), amount),
        recommendation: _generateCategoryRecommendation(category, percentage.toDouble()),
      ));
    }
    
    // Sort by spending amount
    insights.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
    
    return CategoryInsightsAnalysis(
      insights: insights,
      topSpendingCategories: insights.take(5).map((i) => i.category).toList(),
      unusualSpendingCategories: _identifyUnusualSpending(insights),
    );
  }
  
  /// Analyze credit card utilization patterns
  Future<CardUtilizationAnalysis> _analyzeCardUtilization(
    List<Transaction> transactions, 
    List<CreditCard> creditCards,
  ) async {
    final cardUtilizations = <String, CardUtilizationMetrics>{};
    
    for (final card in creditCards) {
      final cardTransactions = transactions.where((t) => t.userCardId == card.id).toList();
      final totalSpent = cardTransactions
          .where((t) => t.type == TransactionType.debit)
          .fold(0.0, (sum, t) => sum + t.amount.abs());
        final utilizationPercentage = (card.creditLimit != null && card.creditLimit! > 0) 
          ? (totalSpent / card.creditLimit!) * 100 
          : 0.0;
      
      cardUtilizations[card.id] = CardUtilizationMetrics(
        cardId: card.id,
        cardName: card.cardName,
        creditLimit: card.creditLimit ?? 0.0,
        currentBalance: totalSpent,
        utilizationPercentage: utilizationPercentage,
        transactionCount: cardTransactions.length,
        averageTransactionAmount: cardTransactions.isNotEmpty ? totalSpent / cardTransactions.length : 0,
        recommendation: _generateUtilizationRecommendation(utilizationPercentage),
        riskLevel: _calculateUtilizationRisk(utilizationPercentage),
      );
    }
    
    return CardUtilizationAnalysis(
      utilizations: cardUtilizations,
      overallUtilization: _calculateOverallUtilization(creditCards, cardUtilizations),
      recommendations: _generateUtilizationRecommendations(cardUtilizations),
    );
  }
  
  /// Identify potential savings opportunities
  Future<List<SavingsOpportunity>> _identifySavingsOpportunities(List<Transaction> transactions) async {
    final opportunities = <SavingsOpportunity>[];
    
    // Subscription analysis
    final subscriptions = _identifySubscriptions(transactions);
    if (subscriptions.isNotEmpty) {
      opportunities.add(SavingsOpportunity(
        type: SavingsOpportunityType.subscriptions,
        title: 'Review Subscriptions',
        description: 'You have ${subscriptions.length} recurring subscriptions. Consider canceling unused ones.',
        potentialSavings: subscriptions.fold(0.0, (sum, t) => sum + t.amount.abs()),
        actionable: true,
        priority: SavingsPriority.medium,
      ));
    }
    
    // Dining out analysis
    final diningTransactions = transactions
        .where((t) => t.category == TransactionCategory.food && t.type == TransactionType.debit)
        .toList();
    if (diningTransactions.isNotEmpty) {
      final monthlyDining = diningTransactions.fold(0.0, (sum, t) => sum + t.amount.abs()) / 12;
      if (monthlyDining > 5000) { // If spending more than ₹5000/month on dining
        opportunities.add(SavingsOpportunity(
          type: SavingsOpportunityType.lifestyle,
          title: 'Optimize Dining Expenses',
          description: 'You spend ₹${monthlyDining.toStringAsFixed(0)}/month on dining. Cooking at home could save 30-40%.',
          potentialSavings: monthlyDining * 0.35 * 12,
          actionable: true,
          priority: SavingsPriority.high,
        ));
      }
    }
    
    // Fuel efficiency analysis
    final fuelTransactions = transactions
        .where((t) => t.category == TransactionCategory.fuel && t.type == TransactionType.debit)
        .toList();
    if (fuelTransactions.isNotEmpty) {
      final monthlyFuel = fuelTransactions.fold(0.0, (sum, t) => sum + t.amount.abs()) / 12;
      opportunities.add(SavingsOpportunity(
        type: SavingsOpportunityType.transportation,
        title: 'Optimize Fuel Spending',
        description: 'Consider carpooling or public transport to reduce your ₹${monthlyFuel.toStringAsFixed(0)}/month fuel costs.',
        potentialSavings: monthlyFuel * 0.2 * 12,
        actionable: true,
        priority: SavingsPriority.medium,
      ));
    }
    
    return opportunities;
  }
  
  /// Analyze reward optimization opportunities
  Future<RewardOptimizationAnalysis> _analyzeRewardOptimization(
    List<Transaction> transactions,
    List<CreditCard> creditCards,
  ) async {
    final categorySpending = <TransactionCategory, double>{};
    
    // Calculate spending by category
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        categorySpending[transaction.category] = 
            (categorySpending[transaction.category] ?? 0) + transaction.amount.abs();
      }
    }
    
    final optimizations = <RewardOptimization>[];
    
    // Analyze each category for better reward opportunities
    for (final entry in categorySpending.entries) {
      final category = entry.key;
      final amount = entry.value;
      
      // Find cards with best rewards for this category
      final bestCards = creditCards
          .where((card) => _getCardRewardRate(card, category) > 1.0)
          .toList();
      
      if (bestCards.isNotEmpty) {        bestCards.sort((a, b) => _getCardRewardRate(b, category).compareTo(_getCardRewardRate(a, category)));
        final bestCard = bestCards.first;
        final currentRewardRate = 1.0; // Assume base rate if not using optimized card
        final bestRewardRate = _getCardRewardRate(bestCard, category);
        
        optimizations.add(RewardOptimization(
          category: category,
          currentAnnualSpending: amount,
          recommendedCard: bestCard.cardName,
          currentRewardRate: currentRewardRate,
          optimizedRewardRate: bestRewardRate,
          additionalRewards: amount * (bestRewardRate - currentRewardRate) / 100,
        ));
      }
    }
    
    return RewardOptimizationAnalysis(
      optimizations: optimizations,
      totalAdditionalRewards: optimizations.fold(0.0, (sum, opt) => sum + opt.additionalRewards),
      topOpportunities: optimizations.take(3).toList(),
    );
  }
  
  /// Generate budget recommendations based on spending patterns
  Future<List<BudgetRecommendation>> _generateBudgetRecommendations(List<Transaction> transactions) async {
    final recommendations = <BudgetRecommendation>[];
    final categorySpending = <TransactionCategory, double>{};
    
    // Calculate monthly spending by category
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        categorySpending[transaction.category] = 
            (categorySpending[transaction.category] ?? 0) + transaction.amount.abs();
      }
    }
    
    final totalSpending = categorySpending.values.fold(0.0, (a, b) => a + b);
    final monthlySpending = totalSpending / 12;
    
    // 50/30/20 rule recommendations
    recommendations.add(BudgetRecommendation(
      category: 'Needs (50%)',
      recommendedBudget: monthlySpending * 0.5,
      currentSpending: _calculateNeedsSpending(categorySpending),
      variance: _calculateNeedsSpending(categorySpending) - (monthlySpending * 0.5),
      recommendation: 'Keep essential expenses like groceries, utilities, and transport under 50% of income',
    ));
    
    recommendations.add(BudgetRecommendation(
      category: 'Wants (30%)',
      recommendedBudget: monthlySpending * 0.3,
      currentSpending: _calculateWantsSpending(categorySpending),
      variance: _calculateWantsSpending(categorySpending) - (monthlySpending * 0.3),
      recommendation: 'Limit discretionary spending like entertainment and dining to 30% of income',
    ));
    
    recommendations.add(BudgetRecommendation(
      category: 'Savings (20%)',
      recommendedBudget: monthlySpending * 0.2,
      currentSpending: 0, // We don't track savings as spending
      variance: -(monthlySpending * 0.2),
      recommendation: 'Aim to save at least 20% of your income for emergency fund and investments',
    ));
    
    return recommendations;
  }
  
  /// Calculate financial health score
  Future<FinancialHealthScore> _calculateFinancialHealthScore(
    List<Transaction> transactions,
    List<CreditCard> creditCards,
  ) async {
    double score = 100.0;    
    final insights = <String>[];    // Calculate overall credit utilization from transactions
    final cardBalances = <String, double>{};
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        final cardKey = transaction.userCardId ?? 'unknown';
        cardBalances[cardKey] = (cardBalances[cardKey] ?? 0) + transaction.amount.abs();
      }
    }
    
    final totalLimit = creditCards.fold(0.0, (sum, card) => sum + (card.creditLimit ?? 0.0));
    final totalBalance = cardBalances.values.fold(0.0, (sum, balance) => sum + balance);
    final utilizationRatio = totalLimit > 0 ? totalBalance / totalLimit : 0.0;
    
    // Credit utilization impact (30% of score)
    if (utilizationRatio > 0.8) {
      score -= 30;
      insights.add('Very high credit utilization (${(utilizationRatio * 100).toStringAsFixed(1)}%)');
    } else if (utilizationRatio > 0.5) {
      score -= 15;
      insights.add('High credit utilization (${(utilizationRatio * 100).toStringAsFixed(1)}%)');
    } else if (utilizationRatio > 0.3) {
      score -= 5;
      insights.add('Moderate credit utilization (${(utilizationRatio * 100).toStringAsFixed(1)}%)');
    }
    
    // Spending consistency (20% of score)
    final monthlySpending = _getMonthlySpendingVariance(transactions);
    if (monthlySpending > 0.4) {
      score -= 20;
      insights.add('Highly inconsistent spending patterns');
    } else if (monthlySpending > 0.2) {
      score -= 10;
      insights.add('Somewhat inconsistent spending patterns');
    }
    
    // Category balance (20% of score)
    final categoryBalance = _analyzeCategoryBalance(transactions);
    if (categoryBalance < 0.6) {
      score -= 20;
      insights.add('Unbalanced spending across categories');
    } else if (categoryBalance < 0.8) {
      score -= 10;
      insights.add('Room for improvement in spending balance');
    }
    
    // Emergency fund indicator (15% of score) - simplified
    final avgMonthlySpending = transactions
        .where((t) => t.type == TransactionType.debit)
        .fold(0.0, (sum, t) => sum + t.amount.abs()) / 12;
    
    // Assume emergency fund is good if spending is controlled
    if (avgMonthlySpending > 50000) {
      score -= 15;
      insights.add('High monthly spending may impact emergency fund building');
    }
    
    // Financial goal progress (15% of score) - placeholder
    // This would require additional data about user's financial goals
    
    return FinancialHealthScore(
      overallScore: score.clamp(0, 100),
      creditUtilizationScore: _calculateCreditUtilizationScore(utilizationRatio),
      spendingConsistencyScore: _calculateSpendingConsistencyScore(monthlySpending),
      categoryBalanceScore: _calculateCategoryBalanceScore(categoryBalance),
      emergencyFundScore: 75, // Placeholder
      insights: insights,
      recommendations: _generateHealthRecommendations(score, insights),
    );
  }
  
  /// Generate predictive insights based on historical data
  Future<List<PredictiveInsight>> _generatePredictiveInsights(List<Transaction> transactions) async {
    final insights = <PredictiveInsight>[];
    
    // Predict next month's spending
    final monthlyTrends = _calculateMonthlySpendingTrend(transactions);
    final predictedSpending = _predictNextMonthSpending(monthlyTrends);
    
    insights.add(PredictiveInsight(
      type: PredictiveInsightType.spending,
      title: 'Next Month Spending Prediction',
      description: 'Based on your spending pattern, you\'re likely to spend ₹${predictedSpending.toStringAsFixed(0)} next month',
      confidence: 0.75,
      actionable: true,
      recommendation: predictedSpending > monthlyTrends.last 
          ? 'Consider setting spending alerts to stay within budget'
          : 'Your spending trend is stable, great job!',
    ));
    
    // Predict reward earnings
    final rewardTrend = _calculateRewardTrend(transactions);
    insights.add(PredictiveInsight(
      type: PredictiveInsightType.rewards,
      title: 'Reward Optimization Opportunity',
      description: 'You could earn ₹${(rewardTrend * 1.5).toStringAsFixed(0)} more in rewards with optimized card usage',
      confidence: 0.8,
      actionable: true,
      recommendation: 'Use category-specific cards for higher reward rates',
    ));
    
    return insights;
  }
  
  // Helper methods
  List<Transaction> _filterTransactionsByDate(List<Transaction> transactions, DateTime start, DateTime end) {
    return transactions.where((t) => 
        t.transactionDate.isAfter(start) && t.transactionDate.isBefore(end)).toList();
  }
  
  DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }
  
  String _calculateTrendDirection(Map<String, double> monthlyData) {
    if (monthlyData.length < 2) return 'stable';
    
    final values = monthlyData.values.toList();
    final recent = values.sublist(max(0, values.length - 3));
    final older = values.sublist(0, min(values.length, 3));
    
    final recentAvg = recent.fold(0.0, (a, b) => a + b) / recent.length;
    final olderAvg = older.fold(0.0, (a, b) => a + b) / older.length;
    
    if (recentAvg > olderAvg * 1.1) return 'increasing';
    if (recentAvg < olderAvg * 0.9) return 'decreasing';
    return 'stable';
  }
  
  double _calculateAverage(List<double> values) {
    if (values.isEmpty) return 0;
    return values.fold(0.0, (a, b) => a + b) / values.length;
  }
  
  double _calculateVolatility(List<double> values) {
    if (values.length < 2) return 0;
    
    final mean = _calculateAverage(values);
    final variance = values.fold(0.0, (sum, value) => sum + pow(value - mean, 2)) / values.length;
    return sqrt(variance) / mean; // Coefficient of variation
  }
  
  String _generateCategoryInsight(TransactionCategory category, double percentage, double amount) {
    if (percentage > 30) {
      return 'High spending in ${category.name} - ${percentage.toStringAsFixed(1)}% of total';
    } else if (percentage > 15) {
      return 'Moderate spending in ${category.name}';
    } else {
      return 'Low spending in ${category.name}';
    }
  }
  
  String _generateCategoryRecommendation(TransactionCategory category, double percentage) {
    switch (category) {
      case TransactionCategory.food:
        return percentage > 25 ? 'Consider meal planning to reduce dining costs' : 'Food spending is well controlled';
      case TransactionCategory.transport:
        return percentage > 20 ? 'Look for carpooling or public transport options' : 'Transportation costs are reasonable';
      case TransactionCategory.entertainment:
        return percentage > 15 ? 'Consider free or low-cost entertainment alternatives' : 'Entertainment spending is balanced';
      default:
        return percentage > 20 ? 'Monitor this category for potential savings' : 'Spending in this category is reasonable';
    }
  }
  
  List<TransactionCategory> _identifyUnusualSpending(List<CategoryInsight> insights) {
    // Identify categories with unusually high spending or sudden spikes
    return insights
        .where((insight) => insight.percentage > 25 || insight.totalSpent > 20000)
        .map((insight) => insight.category)
        .toList();
  }
  
  String _generateUtilizationRecommendation(double utilizationPercentage) {
    if (utilizationPercentage > 80) {
      return 'Very high utilization - pay down balance immediately';
    } else if (utilizationPercentage > 50) {
      return 'High utilization - consider paying down balance';
    } else if (utilizationPercentage > 30) {
      return 'Moderate utilization - monitor spending';
    } else {
      return 'Good utilization level';
    }
  }
  
  String _calculateUtilizationRisk(double utilizationPercentage) {
    if (utilizationPercentage > 80) return 'high';
    if (utilizationPercentage > 50) return 'medium';
    return 'low';
  }
    double _calculateOverallUtilization(List<CreditCard> cards, Map<String, CardUtilizationMetrics> utilizations) {
    final totalLimit = cards.fold(0.0, (sum, card) => sum + (card.creditLimit ?? 0.0));
    final totalBalance = utilizations.values.fold(0.0, (sum, util) => sum + util.currentBalance);
    return totalLimit > 0 ? (totalBalance / totalLimit) * 100 : 0;
  }
  
  List<String> _generateUtilizationRecommendations(Map<String, CardUtilizationMetrics> utilizations) {
    final recommendations = <String>[];
    
    for (final util in utilizations.values) {
      if (util.utilizationPercentage > 80) {
        recommendations.add('Pay down ${util.cardName} immediately - ${util.utilizationPercentage.toStringAsFixed(1)}% utilization');
      }
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Credit utilization is well managed across all cards');
    }
    
    return recommendations;
  }
  
  List<Transaction> _identifySubscriptions(List<Transaction> transactions) {
    // Simple heuristic: transactions with same merchant and similar amounts recurring monthly
    final merchantAmounts = <String, List<double>>{};
    
    for (final transaction in transactions) {
      if (transaction.merchantName != null) {
        merchantAmounts[transaction.merchantName!] ??= [];
        merchantAmounts[transaction.merchantName!]!.add(transaction.amount.abs());
      }
    }
    
    final subscriptions = <Transaction>[];
    for (final entry in merchantAmounts.entries) {
      if (entry.value.length >= 3) { // At least 3 transactions
        final avgAmount = entry.value.fold(0.0, (a, b) => a + b) / entry.value.length;
        final variance = entry.value.fold(0.0, (sum, amount) => sum + pow(amount - avgAmount, 2)) / entry.value.length;
        
        if (variance < avgAmount * 0.1) { // Low variance indicates subscription
          final transaction = transactions.firstWhere((t) => t.merchantName == entry.key);
          subscriptions.add(transaction);
        }
      }
    }
    
    return subscriptions;
  }
    double _getCardRewardRate(CreditCard card, TransactionCategory category) {
    // Simplified reward rate calculation - in real implementation, 
    // this would check the card's actual reward structure
    switch (category) {
      case TransactionCategory.fuel:
        return card.cardName.toLowerCase().contains('fuel') ? 4.0 : 1.0;
      case TransactionCategory.food:
        return card.cardName.toLowerCase().contains('dining') ? 3.0 : 1.0;
      case TransactionCategory.shopping:
        return card.cardName.toLowerCase().contains('shopping') ? 2.0 : 1.0;
      default:
        return 1.0;
    }
  }
  
  double _calculateNeedsSpending(Map<TransactionCategory, double> categorySpending) {
    const needsCategories = [
      TransactionCategory.grocery,
      TransactionCategory.utilities,
      TransactionCategory.transport,
      TransactionCategory.medical,
    ];
    
    return needsCategories.fold(0.0, (sum, category) => sum + (categorySpending[category] ?? 0));
  }
  
  double _calculateWantsSpending(Map<TransactionCategory, double> categorySpending) {
    const wantsCategories = [
      TransactionCategory.entertainment,
      TransactionCategory.shopping,
      TransactionCategory.food,
      TransactionCategory.travel,
    ];
    
    return wantsCategories.fold(0.0, (sum, category) => sum + (categorySpending[category] ?? 0));
  }
    double _getMonthlySpendingVariance(List<Transaction> transactions) {
    final monthlyTotals = <String, double>{};
    
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        final monthKey = '${transaction.transactionDate.year}-${transaction.transactionDate.month}';
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + transaction.amount.abs();
      }
    }
    
    if (monthlyTotals.length < 2) return 0;
    
    final values = monthlyTotals.values.toList();
    return _calculateVolatility(values);
  }
  
  double _analyzeCategoryBalance(List<Transaction> transactions) {
    final categoryTotals = <TransactionCategory, double>{};
    
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        categoryTotals[transaction.category] = 
            (categoryTotals[transaction.category] ?? 0) + transaction.amount.abs();
      }
    }
    
    if (categoryTotals.isEmpty) return 1.0;
    
    final totalSpending = categoryTotals.values.fold(0.0, (a, b) => a + b);
    final maxCategorySpending = categoryTotals.values.reduce(max);
    
    // Balance score: 1.0 if perfectly balanced, lower if one category dominates
    return 1.0 - (maxCategorySpending / totalSpending);
  }
  
  double _calculateCreditUtilizationScore(double utilizationRatio) {
    if (utilizationRatio <= 0.1) return 100;
    if (utilizationRatio <= 0.3) return 90;
    if (utilizationRatio <= 0.5) return 70;
    if (utilizationRatio <= 0.8) return 40;
    return 20;
  }
  
  double _calculateSpendingConsistencyScore(double variance) {
    if (variance <= 0.1) return 100;
    if (variance <= 0.2) return 80;
    if (variance <= 0.4) return 60;
    return 40;
  }
  
  double _calculateCategoryBalanceScore(double balance) {
    return balance * 100;
  }
  
  List<String> _generateHealthRecommendations(double score, List<String> insights) {
    final recommendations = <String>[];
    
    if (score >= 80) {
      recommendations.add('Excellent financial health! Keep up the good work.');
    } else if (score >= 60) {
      recommendations.add('Good financial health with room for improvement.');
      if (insights.any((i) => i.contains('utilization'))) {
        recommendations.add('Focus on reducing credit card balances.');
      }
    } else {
      recommendations.add('Financial health needs attention.');
      recommendations.add('Create a debt payoff plan and budget.');
      recommendations.add('Consider speaking with a financial advisor.');
    }
    
    return recommendations;
  }
  
  List<double> _calculateMonthlySpendingTrend(List<Transaction> transactions) {
    final monthlyTotals = <String, double>{};
    
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.debit) {
        final monthKey = '${transaction.transactionDate.year}-${transaction.transactionDate.month.toString().padLeft(2, '0')}';
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + transaction.amount.abs();
      }
    }
    
    final sortedKeys = monthlyTotals.keys.toList()..sort();
    return sortedKeys.map((key) => monthlyTotals[key]!).toList();
  }
  
  double _predictNextMonthSpending(List<double> monthlyTrends) {
    if (monthlyTrends.length < 3) {
      return monthlyTrends.isNotEmpty ? monthlyTrends.last : 0;
    }
    
    // Simple linear regression for prediction
    final n = monthlyTrends.length;
    final x = List.generate(n, (i) => i.toDouble());
    final y = monthlyTrends;
    
    final xMean = x.fold(0.0, (a, b) => a + b) / n;
    final yMean = y.fold(0.0, (a, b) => a + b) / n;
    
    double numerator = 0;
    double denominator = 0;
    
    for (int i = 0; i < n; i++) {
      numerator += (x[i] - xMean) * (y[i] - yMean);
      denominator += pow(x[i] - xMean, 2);
    }
    
    final slope = denominator != 0 ? numerator / denominator : 0;
    final intercept = yMean - slope * xMean;
    
    // Predict next month (n)
    return intercept + slope * n;
  }
  
  double _calculateRewardTrend(List<Transaction> transactions) {
    return transactions
        .where((t) => t.rewardEarned != null)
        .fold(0.0, (sum, t) => sum + t.rewardEarned!) / 12;
  }
}

// Enhanced analytics models
class FinancialInsights {
  final SpendingTrendAnalysis spendingTrends;
  final CategoryInsightsAnalysis categoryInsights;
  final CardUtilizationAnalysis cardUtilization;
  final List<SavingsOpportunity> savingsOpportunities;
  final RewardOptimizationAnalysis rewardOptimization;
  final List<BudgetRecommendation> budgetRecommendations;
  final FinancialHealthScore financialHealthScore;
  final List<PredictiveInsight> predictiveInsights;
  
  const FinancialInsights({
    required this.spendingTrends,
    required this.categoryInsights,
    required this.cardUtilization,
    required this.savingsOpportunities,
    required this.rewardOptimization,
    required this.budgetRecommendations,
    required this.financialHealthScore,
    required this.predictiveInsights,
  });
}

class SpendingTrendAnalysis {
  final Map<String, double> monthlySpending;
  final Map<String, double> weeklySpending;
  final Map<String, double> dailySpending;
  final String trendDirection;
  final double averageMonthlySpending;
  final double spendingVolatility;
  
  const SpendingTrendAnalysis({
    required this.monthlySpending,
    required this.weeklySpending,
    required this.dailySpending,
    required this.trendDirection,
    required this.averageMonthlySpending,
    required this.spendingVolatility,
  });
}

class CategoryInsightsAnalysis {
  final List<CategoryInsight> insights;
  final List<TransactionCategory> topSpendingCategories;
  final List<TransactionCategory> unusualSpendingCategories;
  
  const CategoryInsightsAnalysis({
    required this.insights,
    required this.topSpendingCategories,
    required this.unusualSpendingCategories,
  });
}

class CategoryInsight {
  final TransactionCategory category;
  final double totalSpent;
  final double percentage;
  final int transactionCount;
  final double averageTransactionAmount;
  final Map<String, double> monthlyTrend;
  final String insight;
  final String recommendation;
  
  const CategoryInsight({
    required this.category,
    required this.totalSpent,
    required this.percentage,
    required this.transactionCount,
    required this.averageTransactionAmount,
    required this.monthlyTrend,
    required this.insight,
    required this.recommendation,
  });
}

class CardUtilizationAnalysis {
  final Map<String, CardUtilizationMetrics> utilizations;
  final double overallUtilization;
  final List<String> recommendations;
  
  const CardUtilizationAnalysis({
    required this.utilizations,
    required this.overallUtilization,
    required this.recommendations,
  });
}

class CardUtilizationMetrics {
  final String cardId;
  final String cardName;
  final double creditLimit;
  final double currentBalance;
  final double utilizationPercentage;
  final int transactionCount;
  final double averageTransactionAmount;
  final String recommendation;
  final String riskLevel;
  
  const CardUtilizationMetrics({
    required this.cardId,
    required this.cardName,
    required this.creditLimit,
    required this.currentBalance,
    required this.utilizationPercentage,
    required this.transactionCount,
    required this.averageTransactionAmount,
    required this.recommendation,
    required this.riskLevel,
  });
}

class SavingsOpportunity {
  final SavingsOpportunityType type;
  final String title;
  final String description;
  final double potentialSavings;
  final bool actionable;
  final SavingsPriority priority;
  
  const SavingsOpportunity({
    required this.type,
    required this.title,
    required this.description,
    required this.potentialSavings,
    required this.actionable,
    required this.priority,
  });
}

enum SavingsOpportunityType {
  subscriptions,
  lifestyle,
  transportation,
  utilities,
  insurance,
}

enum SavingsPriority {
  low,
  medium,
  high,
}

class RewardOptimizationAnalysis {
  final List<RewardOptimization> optimizations;
  final double totalAdditionalRewards;
  final List<RewardOptimization> topOpportunities;
  
  const RewardOptimizationAnalysis({
    required this.optimizations,
    required this.totalAdditionalRewards,
    required this.topOpportunities,
  });
}

class RewardOptimization {
  final TransactionCategory category;
  final double currentAnnualSpending;
  final String recommendedCard;
  final double currentRewardRate;
  final double optimizedRewardRate;
  final double additionalRewards;
  
  const RewardOptimization({
    required this.category,
    required this.currentAnnualSpending,
    required this.recommendedCard,
    required this.currentRewardRate,
    required this.optimizedRewardRate,
    required this.additionalRewards,
  });
}

class BudgetRecommendation {
  final String category;
  final double recommendedBudget;
  final double currentSpending;
  final double variance;
  final String recommendation;
  
  const BudgetRecommendation({
    required this.category,
    required this.recommendedBudget,
    required this.currentSpending,
    required this.variance,
    required this.recommendation,
  });
}

class FinancialHealthScore {
  final double overallScore;
  final double creditUtilizationScore;
  final double spendingConsistencyScore;
  final double categoryBalanceScore;
  final double emergencyFundScore;
  final List<String> insights;
  final List<String> recommendations;
  
  const FinancialHealthScore({
    required this.overallScore,
    required this.creditUtilizationScore,
    required this.spendingConsistencyScore,
    required this.categoryBalanceScore,
    required this.emergencyFundScore,
    required this.insights,
    required this.recommendations,
  });
}

class PredictiveInsight {
  final PredictiveInsightType type;
  final String title;
  final String description;
  final double confidence;
  final bool actionable;
  final String recommendation;
  
  const PredictiveInsight({
    required this.type,
    required this.title,
    required this.description,
    required this.confidence,
    required this.actionable,
    required this.recommendation,
  });
}

enum PredictiveInsightType {
  spending,
  rewards,
  utilization,
  savings,
}
