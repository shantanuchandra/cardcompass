import 'package:json_annotation/json_annotation.dart';

part 'analytics.g.dart';

/// Model for monthly spending data
@JsonSerializable()
class MonthlySpending {
  final String month;
  final double totalSpending;
  final double rewardsEarned;
  
  const MonthlySpending({
    required this.month,
    required this.totalSpending,
    required this.rewardsEarned,
  });
  
  factory MonthlySpending.fromJson(Map<String, dynamic> json) => _$MonthlySpendingFromJson(json);
  
  Map<String, dynamic> toJson() => _$MonthlySpendingToJson(this);
}

/// Model for spending breakdown by category
@JsonSerializable()
class CategorySpending {
  final String category;
  final double amount;
  final double percentage;
  final int transactionCount;
  
  const CategorySpending({
    required this.category,
    required this.amount,
    required this.percentage,
    required this.transactionCount,
  });
  
  factory CategorySpending.fromJson(Map<String, dynamic> json) => _$CategorySpendingFromJson(json);
  
  Map<String, dynamic> toJson() => _$CategorySpendingToJson(this);
}

/// Model for spending analysis
@JsonSerializable()
class SpendingAnalysis {
  final double totalMonthlySpending;
  final Map<String, double> categoryBreakdown;
  final List<String> topCategories;
  final double averageTransactionAmount;
  final int totalTransactions;
  
  const SpendingAnalysis({
    required this.totalMonthlySpending,
    required this.categoryBreakdown,
    required this.topCategories,
    required this.averageTransactionAmount,
    required this.totalTransactions,
  });
  
  factory SpendingAnalysis.fromJson(Map<String, dynamic> json) => _$SpendingAnalysisFromJson(json);
  
  Map<String, dynamic> toJson() => _$SpendingAnalysisToJson(this);
}
