// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_balance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RewardBalance _$RewardBalanceFromJson(Map<String, dynamic> json) =>
    RewardBalance(
      id: json['id'] as String,
      userId: json['userId'] as String,
      userCardId: json['userCardId'] as String,
      rewardType: json['rewardType'] as String,
      availableBalance: (json['availableBalance'] as num).toDouble(),
      totalEarned: (json['totalEarned'] as num).toDouble(),
      totalRedeemed: (json['totalRedeemed'] as num).toDouble(),
      pendingBalance: (json['pendingBalance'] as num?)?.toDouble() ?? 0.0,
      expiryDate: json['expiryDate'] == null
          ? null
          : DateTime.parse(json['expiryDate'] as String),
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$RewardBalanceToJson(RewardBalance instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'userCardId': instance.userCardId,
      'rewardType': instance.rewardType,
      'availableBalance': instance.availableBalance,
      'totalEarned': instance.totalEarned,
      'totalRedeemed': instance.totalRedeemed,
      'pendingBalance': instance.pendingBalance,
      'expiryDate': instance.expiryDate?.toIso8601String(),
      'metadata': instance.metadata,
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
    };
