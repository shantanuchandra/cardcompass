// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Transaction _$TransactionFromJson(Map<String, dynamic> json) => Transaction(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userCardId: json['userCardId'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'INR',
      description: json['description'] as String,
      merchantName: json['merchantName'] as String?,
      category:
          $enumDecodeNullable(_$TransactionCategoryEnumMap, json['category']) ??
              TransactionCategory.other,
      type: $enumDecodeNullable(_$TransactionTypeEnumMap, json['type']) ??
          TransactionType.debit,
      transactionDate: DateTime.parse(json['transactionDate'] as String),
      location: json['location'] as String?,
      rewardEarned: (json['rewardEarned'] as num?)?.toDouble(),
      rewardType: json['rewardType'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      statementId: json['statementId'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$TransactionToJson(Transaction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'userCardId': instance.userCardId,
      'amount': instance.amount,
      'currency': instance.currency,
      'description': instance.description,
      'merchantName': instance.merchantName,
      'category': _$TransactionCategoryEnumMap[instance.category]!,
      'type': _$TransactionTypeEnumMap[instance.type]!,
      'transactionDate': instance.transactionDate.toIso8601String(),
      'location': instance.location,
      'rewardEarned': instance.rewardEarned,
      'rewardType': instance.rewardType,
      'metadata': instance.metadata,
      'statementId': instance.statementId,
      'isRecurring': instance.isRecurring,
      'createdAt': instance.createdAt.toIso8601String(),
    };

const _$TransactionCategoryEnumMap = {
  TransactionCategory.food: 'food',
  TransactionCategory.fuel: 'fuel',
  TransactionCategory.grocery: 'grocery',
  TransactionCategory.entertainment: 'entertainment',
  TransactionCategory.travel: 'travel',
  TransactionCategory.shopping: 'shopping',
  TransactionCategory.utilities: 'utilities',
  TransactionCategory.insurance: 'insurance',
  TransactionCategory.medical: 'medical',
  TransactionCategory.education: 'education',
  TransactionCategory.investment: 'investment',
  TransactionCategory.transport: 'transport',
  TransactionCategory.rental: 'rental',
  TransactionCategory.subscription: 'subscription',
  TransactionCategory.gift: 'gift',
  TransactionCategory.other: 'other',
};

const _$TransactionTypeEnumMap = {
  TransactionType.debit: 'debit',
  TransactionType.credit: 'credit',
  TransactionType.refund: 'refund',
  TransactionType.fee: 'fee',
  TransactionType.interest: 'interest',
  TransactionType.reward: 'reward',
};
