// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analytics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MonthlySpending _$MonthlySpendingFromJson(Map<String, dynamic> json) =>
    MonthlySpending(
      month: json['month'] as String,
      totalSpending: (json['totalSpending'] as num).toDouble(),
      rewardsEarned: (json['rewardsEarned'] as num).toDouble(),
    );

Map<String, dynamic> _$MonthlySpendingToJson(MonthlySpending instance) =>
    <String, dynamic>{
      'month': instance.month,
      'totalSpending': instance.totalSpending,
      'rewardsEarned': instance.rewardsEarned,
    };

CategorySpending _$CategorySpendingFromJson(Map<String, dynamic> json) =>
    CategorySpending(
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      percentage: (json['percentage'] as num).toDouble(),
      transactionCount: (json['transactionCount'] as num).toInt(),
    );

Map<String, dynamic> _$CategorySpendingToJson(CategorySpending instance) =>
    <String, dynamic>{
      'category': instance.category,
      'amount': instance.amount,
      'percentage': instance.percentage,
      'transactionCount': instance.transactionCount,
    };

SpendingAnalysis _$SpendingAnalysisFromJson(Map<String, dynamic> json) =>
    SpendingAnalysis(
      totalMonthlySpending: (json['totalMonthlySpending'] as num).toDouble(),
      categoryBreakdown:
          (json['categoryBreakdown'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ),
      topCategories: (json['topCategories'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      averageTransactionAmount:
          (json['averageTransactionAmount'] as num).toDouble(),
      totalTransactions: (json['totalTransactions'] as num).toInt(),
    );

Map<String, dynamic> _$SpendingAnalysisToJson(SpendingAnalysis instance) =>
    <String, dynamic>{
      'totalMonthlySpending': instance.totalMonthlySpending,
      'categoryBreakdown': instance.categoryBreakdown,
      'topCategories': instance.topCategories,
      'averageTransactionAmount': instance.averageTransactionAmount,
      'totalTransactions': instance.totalTransactions,
    };
