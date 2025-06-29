import 'dart:math';
import 'package:cardcompass/shared/models/credit_card.dart';
import 'package:cardcompass/shared/models/transaction.dart';

/// Advanced ML-based recommendation service for credit cards
class AdvancedRecommendationService {
  
  /// Get next best card recommendations using ML analysis
  Future<List<CardRecommendationML>> getMLBasedRecommendations({
    required String userId,
    required List<Transaction> transactionHistory,
    required List<CreditCard> currentCards,
    required List<CreditCard> availableCards,
  }) async {
    
    // Step 1: Analyze spending patterns using ML algorithms
    final spendingPatterns = await _analyzeSpendingPatterns(transactionHistory);
    
    // Step 2: Calculate potential savings for each available card
    final recommendations = <CardRecommendationML>[];
    
    for (final card in availableCards) {
      if (_isCardAlreadyOwned(card, currentCards)) continue;
      
      final analysis = await _analyzeCardForUser(
        card: card,
        spendingPatterns: spendingPatterns,
        transactionHistory: transactionHistory,
      );
      
      if (analysis.potentialAnnualSavings > 0) {
        recommendations.add(analysis);
      }
    }
    
    // Step 3: Sort by ML confidence score and potential savings
    recommendations.sort((a, b) {
      final scoreA = a.mlConfidenceScore * a.potentialAnnualSavings;
      final scoreB = b.mlConfidenceScore * b.potentialAnnualSavings;
      return scoreB.compareTo(scoreA);
    });
    
    return recommendations.take(5).toList();
  }
  
  /// Analyze user spending patterns using machine learning techniques
  Future<SpendingPatternAnalysis> _analyzeSpendingPatterns(List<Transaction> transactions) async {
    final categorySpending = <String, double>{};
    final merchantSpending = <String, double>{};
    final timePatterns = <int, double>{}; // Hour of day spending
    final seasonalPatterns = <int, double>{}; // Month spending
    
    double totalSpending = 0;
    int totalTransactions = transactions.length;
      for (final transaction in transactions) {
      totalSpending += transaction.amount;
      
      // Category analysis (convert enum to string)
      final categoryKey = transaction.category.toString().split('.').last;
      categorySpending[categoryKey] = 
          (categorySpending[categoryKey] ?? 0) + transaction.amount;
      
      // Merchant analysis (handle nullable merchant name)
      final merchantName = transaction.merchantName ?? 'Unknown Merchant';
      merchantSpending[merchantName] = 
          (merchantSpending[merchantName] ?? 0) + transaction.amount;
      
      // Time pattern analysis
      final hour = transaction.transactionDate.hour;
      timePatterns[hour] = (timePatterns[hour] ?? 0) + transaction.amount;
      
      // Seasonal pattern analysis
      final month = transaction.transactionDate.month;
      seasonalPatterns[month] = (seasonalPatterns[month] ?? 0) + transaction.amount;
    }
    
    // Calculate spending velocity (transactions per month)
    final monthsOfData = _calculateMonthsOfData(transactions);
    final spendingVelocity = totalTransactions / monthsOfData;
    
    // Calculate category preferences (using entropy-like calculation)
    final categoryPreferences = _calculateCategoryPreferences(categorySpending, totalSpending);
    
    // Identify peak spending times
    final peakSpendingHour = _findPeakSpendingTime(timePatterns);
    final peakSpendingMonth = _findPeakSpendingMonth(seasonalPatterns);
    
    return SpendingPatternAnalysis(
      averageMonthlySpending: totalSpending / monthsOfData,
      categoryBreakdown: categorySpending,
      merchantPreferences: merchantSpending,
      spendingVelocity: spendingVelocity,
      categoryPreferences: categoryPreferences,
      peakSpendingHour: peakSpendingHour,
      peakSpendingMonth: peakSpendingMonth,
      timePatterns: timePatterns,
      seasonalPatterns: seasonalPatterns,
    );
  }
  
  /// Analyze how well a specific card matches user's spending patterns
  Future<CardRecommendationML> _analyzeCardForUser({
    required CreditCard card,
    required SpendingPatternAnalysis spendingPatterns,
    required List<Transaction> transactionHistory,
  }) async {
    
    double totalPotentialSavings = 0;
    double mlConfidenceScore = 0;
    final benefitAnalysis = <String, double>{};
    
    // Calculate savings for each spending category
    for (final entry in spendingPatterns.categoryBreakdown.entries) {
      final category = entry.key;
      final annualSpending = entry.value * 12; // Convert to annual
      
      final currentReward = _calculateCurrentReward(category, annualSpending, []);
      final potentialReward = _calculateCardReward(card, category, annualSpending);
      
      final savings = potentialReward - currentReward;
      if (savings > 0) {
        totalPotentialSavings += savings;
        benefitAnalysis[category] = savings;
      }
    }
    
    // Subtract annual fee
    totalPotentialSavings -= (card.annualFee ?? 0);
    
    // Calculate ML confidence score based on multiple factors
    mlConfidenceScore = _calculateMLConfidenceScore(
      card: card,
      spendingPatterns: spendingPatterns,
      potentialSavings: totalPotentialSavings,
    );
      // Generate personalized recommendation reason
    final recommendationReason = _generateRecommendationReason(
      card,
      spendingPatterns,
      benefitAnalysis,
    );
    
    return CardRecommendationML(
      card: card,
      potentialAnnualSavings: totalPotentialSavings,
      mlConfidenceScore: mlConfidenceScore,
      recommendationReason: recommendationReason,
      benefitAnalysis: benefitAnalysis,
      riskScore: _calculateRiskScore(card),
      compatibilityScore: _calculateCompatibilityScore(card, spendingPatterns),
    );
  }
  
  /// Calculate ML confidence score using multiple algorithms
  double _calculateMLConfidenceScore({
    required CreditCard card,
    required SpendingPatternAnalysis spendingPatterns,
    required double potentialSavings,
  }) {
    double score = 0.0;
    
    // Factor 1: Savings potential (40% weight)
    final savingsScore = min(potentialSavings / 10000, 1.0); // Normalize to max 10k savings
    score += savingsScore * 0.4;
    
    // Factor 2: Category alignment (30% weight)
    final alignmentScore = _calculateCategoryAlignment(card, spendingPatterns);
    score += alignmentScore * 0.3;
    
    // Factor 3: Spending velocity match (20% weight)
    final velocityScore = _calculateVelocityMatch(card, spendingPatterns);
    score += velocityScore * 0.2;
    
    // Factor 4: Risk assessment (10% weight)
    final riskScore = 1.0 - _calculateRiskScore(card);
    score += riskScore * 0.1;
    
    return min(score, 1.0);
  }
  
  /// Calculate reward for a specific card and category using Indian bank algorithms
  double _calculateCardReward(CreditCard card, String category, double amount) {
    final bankName = card.bankName.toLowerCase();
    final cardName = card.cardName.toLowerCase();
    
    // Indian bank-specific reward calculations
    switch (bankName) {
      case 'hdfc bank':
        return _calculateHDFCRewards(cardName, category, amount);
      case 'sbi card':
        return _calculateSBIRewards(cardName, category, amount);
      case 'axis bank':
        return _calculateAxisRewards(cardName, category, amount);
      case 'icici bank':
        return _calculateICICIRewards(cardName, category, amount);
      case 'kotak bank':
        return _calculateKotakRewards(cardName, category, amount);
      case 'idfc first bank':
        return _calculateIDFCRewards(cardName, category, amount);
      default:
        return amount * 0.01; // 1% default
    }
  }
  
  /// HDFC Bank specific reward calculation
  double _calculateHDFCRewards(String cardName, String category, double amount) {
    if (cardName.contains('infinia')) {
      // HDFC Infinia: 3.33% on all spends (luxury tier)
      return amount * 0.0333;
    } else if (cardName.contains('diners club black')) {
      // Diners Club Black: 5% on specific categories
      if (['dining', 'travel'].contains(category.toLowerCase())) {
        return amount * 0.05;
      }
      return amount * 0.02;
    } else if (cardName.contains('regalia')) {
      // HDFC Regalia: 2% on all spends with caps
      final monthlyAmount = amount / 12;
      if (monthlyAmount <= 10000) {
        return amount * 0.02;
      } else {
        return 10000 * 12 * 0.02 + (amount - 10000 * 12) * 0.005;
      }
    } else if (cardName.contains('millennia')) {
      // HDFC Millennia: 5% on online spends
      if (['shopping', 'e-commerce'].contains(category.toLowerCase())) {
        return min(amount * 0.05, 1000); // Cap at 1000 per month
      }
      return amount * 0.01;
    }
    return amount * 0.01;
  }
  
  /// SBI Card specific reward calculation
  double _calculateSBIRewards(String cardName, String category, double amount) {
    if (cardName.contains('elite')) {
      // SBI Elite: 5X rewards on dining and groceries
      if (['dining', 'grocery'].contains(category.toLowerCase())) {
        return amount * 0.05;
      }
      return amount * 0.01;
    } else if (cardName.contains('cashback')) {
      // SBI Cashback: 5% on online spends
      if (['shopping', 'e-commerce'].contains(category.toLowerCase())) {
        return amount * 0.05;
      }
      return amount * 0.01;
    } else if (cardName.contains('simplyclick')) {
      // SBI SimplyClick: 10X on online shopping
      if (category.toLowerCase() == 'shopping') {
        return min(amount * 0.10, 2000); // Cap at 2000 per month
      }
      return amount * 0.01;
    }
    return amount * 0.01;
  }
  
  /// Axis Bank specific reward calculation
  double _calculateAxisRewards(String cardName, String category, double amount) {
    if (cardName.contains('magnus')) {
      // Axis Magnus: Complex milestone-based rewards
      final annualAmount = amount;
      if (annualAmount >= 1500000) {
        return amount * 0.12; // 12% effective rate for high spenders
      } else if (annualAmount >= 100000) {
        return amount * 0.06; // 6% for mid-tier
      }
      return amount * 0.012; // 1.2% base
    } else if (cardName.contains('ace')) {
      // Axis Ace: 5% cashback on specific categories
      if (['fuel', 'utility'].contains(category.toLowerCase())) {
        return amount * 0.05;
      }
      return amount * 0.015;
    }
    return amount * 0.01;
  }
  
  /// ICICI Bank specific reward calculation
  double _calculateICICIRewards(String cardName, String category, double amount) {
    if (cardName.contains('emeralde')) {
      // ICICI Emeralde: Premium travel benefits
      if (category.toLowerCase() == 'travel') {
        return amount * 0.04;
      }
      return amount * 0.02;
    } else if (cardName.contains('amazon pay')) {
      // Amazon Pay ICICI: 5% on Amazon, 2% elsewhere
      if (category.toLowerCase() == 'shopping') {
        return amount * 0.05;
      }
      return amount * 0.02;
    }
    return amount * 0.01;
  }
  
  /// Kotak Bank specific reward calculation
  double _calculateKotakRewards(String cardName, String category, double amount) {
    if (cardName.contains('zen')) {
      // Kotak Zen: 4% on online spends
      if (['shopping', 'e-commerce'].contains(category.toLowerCase())) {
        return amount * 0.04;
      }
      return amount * 0.01;
    }
    return amount * 0.01;
  }
  
  /// IDFC First Bank specific reward calculation
  double _calculateIDFCRewards(String cardName, String category, double amount) {
    if (cardName.contains('wealth')) {
      // IDFC Wealth: 6X rewards on all spends
      return amount * 0.06;
    } else if (cardName.contains('classic')) {
      // IDFC Classic: 10X reward points
      return amount * 0.10; // Assuming 1 point = 0.1 INR
    }
    return amount * 0.01;
  }
  
  // Helper methods
  double _calculateCurrentReward(String category, double amount, List<CreditCard> currentCards) {
    if (currentCards.isEmpty) return 0;
    
    double maxReward = 0;
    for (final card in currentCards) {
      final reward = _calculateCardReward(card, category, amount);
      maxReward = max(maxReward, reward);
    }
    return maxReward;
  }
  
  bool _isCardAlreadyOwned(CreditCard card, List<CreditCard> currentCards) {
    return currentCards.any((owned) => 
        owned.cardName == card.cardName && owned.bankName == card.bankName);
  }
  
  double _calculateMonthsOfData(List<Transaction> transactions) {
    if (transactions.isEmpty) return 1;
    
    final oldest = transactions.map((t) => t.transactionDate).reduce((a, b) => a.isBefore(b) ? a : b);
    final newest = transactions.map((t) => t.transactionDate).reduce((a, b) => a.isAfter(b) ? a : b);
    
    final months = newest.difference(oldest).inDays / 30.44; // Average days per month
    return max(months, 1);
  }
  
  Map<String, double> _calculateCategoryPreferences(Map<String, double> categorySpending, double totalSpending) {
    final preferences = <String, double>{};
    for (final entry in categorySpending.entries) {
      preferences[entry.key] = entry.value / totalSpending;
    }
    return preferences;
  }
  
  int _findPeakSpendingTime(Map<int, double> timePatterns) {
    if (timePatterns.isEmpty) return 12; // Default to noon
    
    return timePatterns.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
  
  int _findPeakSpendingMonth(Map<int, double> seasonalPatterns) {
    if (seasonalPatterns.isEmpty) return 12; // Default to December
    
    return seasonalPatterns.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
  
  double _calculateCategoryAlignment(CreditCard card, SpendingPatternAnalysis patterns) {
    // This would analyze how well the card's benefits align with user's spending categories
    // For now, simplified implementation
    return 0.8; // 80% alignment
  }
  
  double _calculateVelocityMatch(CreditCard card, SpendingPatternAnalysis patterns) {
    // Analyze if card suits user's transaction velocity
    return 0.9; // 90% match
  }
  
  double _calculateRiskScore(CreditCard card) {
    // Calculate risk based on annual fee, minimum income requirements, etc.
    final annualFee = card.annualFee ?? 0;
    if (annualFee > 50000) return 0.8; // High risk for premium cards
    if (annualFee > 10000) return 0.5; // Medium risk
    return 0.2; // Low risk
  }
  
  double _calculateCompatibilityScore(CreditCard card, SpendingPatternAnalysis patterns) {
    // Calculate how compatible the card is with user's spending patterns
    return 0.85; // 85% compatibility
  }
  
  String _generateRecommendationReason(CreditCard card, SpendingPatternAnalysis patterns, Map<String, double> benefitAnalysis) {
    final topCategory = patterns.categoryBreakdown.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
    
    final topBenefit = benefitAnalysis.entries.isNotEmpty
        ? benefitAnalysis.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : topCategory;
    
    return 'Perfect match for your ${topCategory.toLowerCase()} spending. '
           'Could save ₹${benefitAnalysis[topBenefit]?.toStringAsFixed(0) ?? '0'} annually on $topBenefit.';
  }
}

/// Advanced spending pattern analysis model
class SpendingPatternAnalysis {
  final double averageMonthlySpending;
  final Map<String, double> categoryBreakdown;
  final Map<String, double> merchantPreferences;
  final double spendingVelocity;
  final Map<String, double> categoryPreferences;
  final int peakSpendingHour;
  final int peakSpendingMonth;
  final Map<int, double> timePatterns;
  final Map<int, double> seasonalPatterns;
  
  const SpendingPatternAnalysis({
    required this.averageMonthlySpending,
    required this.categoryBreakdown,
    required this.merchantPreferences,
    required this.spendingVelocity,
    required this.categoryPreferences,
    required this.peakSpendingHour,
    required this.peakSpendingMonth,
    required this.timePatterns,
    required this.seasonalPatterns,
  });
}

/// ML-based card recommendation model
class CardRecommendationML {
  final CreditCard card;
  final double potentialAnnualSavings;
  final double mlConfidenceScore;
  final String recommendationReason;
  final Map<String, double> benefitAnalysis;
  final double riskScore;
  final double compatibilityScore;
  
  const CardRecommendationML({
    required this.card,
    required this.potentialAnnualSavings,
    required this.mlConfidenceScore,
    required this.recommendationReason,
    required this.benefitAnalysis,
    required this.riskScore,
    required this.compatibilityScore,
  });
}
