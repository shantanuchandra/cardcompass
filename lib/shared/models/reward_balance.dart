import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'reward_balance.g.dart';

/// Reward balance model for tracking accumulated points/cashback per card
@HiveType(typeId: 7)
@JsonSerializable()
class RewardBalance {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final String userCardId;

  @HiveField(3)
  final String rewardType; // 'points', 'cashback', 'miles', 'vouchers'

  @HiveField(4)
  final double availableBalance;

  @HiveField(5)
  final double totalEarned;

  @HiveField(6)
  final double totalRedeemed;

  @HiveField(7)
  final double pendingBalance; // Points not yet credited

  @HiveField(8)
  final DateTime? expiryDate; // When points expire

  @HiveField(9)
  final Map<String, dynamic> metadata; // Additional info like redemption options

  @HiveField(10)
  final DateTime lastUpdated;

  @HiveField(11)
  final DateTime createdAt;

  const RewardBalance({
    required this.id,
    required this.userId,
    required this.userCardId,
    required this.rewardType,
    required this.availableBalance,
    required this.totalEarned,
    required this.totalRedeemed,
    this.pendingBalance = 0.0,
    this.expiryDate,
    this.metadata = const {},
    required this.lastUpdated,
    required this.createdAt,
  });

  factory RewardBalance.fromJson(Map<String, dynamic> json) {
    return RewardBalance(
      id: json['id'],
      userId: json['user_id'],
      userCardId: json['user_card_id'],
      rewardType: json['reward_type'],
      availableBalance: (json['available_balance'] as num).toDouble(),
      totalEarned: (json['total_earned'] as num).toDouble(),
      totalRedeemed: (json['total_redeemed'] as num).toDouble(),
      pendingBalance: (json['pending_balance'] as num?)?.toDouble() ?? 0.0,
      expiryDate: json['expiry_date'] != null 
          ? DateTime.parse(json['expiry_date']) 
          : null,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      lastUpdated: DateTime.parse(json['last_updated']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_card_id': userCardId,
      'reward_type': rewardType,
      'available_balance': availableBalance,
      'total_earned': totalEarned,
      'total_redeemed': totalRedeemed,
      'pending_balance': pendingBalance,
      'expiry_date': expiryDate?.toIso8601String(),
      'metadata': metadata,
      'last_updated': lastUpdated.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Calculate total points balance including pending
  double get totalBalance => availableBalance + pendingBalance;

  /// Check if points are expiring soon (within 30 days)
  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final now = DateTime.now();
    final daysUntilExpiry = expiryDate!.difference(now).inDays;
    return daysUntilExpiry <= 30 && daysUntilExpiry > 0;
  }

  /// Get formatted balance string
  String get formattedBalance {
    switch (rewardType.toLowerCase()) {
      case 'cashback':
        return '₹${availableBalance.toStringAsFixed(2)}';
      case 'points':
        return '${availableBalance.toStringAsFixed(0)} pts';
      case 'miles':
        return '${availableBalance.toStringAsFixed(0)} miles';
      default:
        return availableBalance.toStringAsFixed(2);
    }
  }

  RewardBalance copyWith({
    String? id,
    String? userId,
    String? userCardId,
    String? rewardType,
    double? availableBalance,
    double? totalEarned,
    double? totalRedeemed,
    double? pendingBalance,
    DateTime? expiryDate,
    Map<String, dynamic>? metadata,
    DateTime? lastUpdated,
    DateTime? createdAt,
  }) {
    return RewardBalance(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userCardId: userCardId ?? this.userCardId,
      rewardType: rewardType ?? this.rewardType,
      availableBalance: availableBalance ?? this.availableBalance,
      totalEarned: totalEarned ?? this.totalEarned,
      totalRedeemed: totalRedeemed ?? this.totalRedeemed,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      expiryDate: expiryDate ?? this.expiryDate,
      metadata: metadata ?? this.metadata,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'RewardBalance(id: $id, rewardType: $rewardType, availableBalance: $availableBalance)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RewardBalance && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Model for reward redemption tracking
@HiveType(typeId: 8)
class RewardRedemption {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String userId;

  @HiveField(2)
  final String userCardId;

  @HiveField(3)
  final String rewardBalanceId;

  @HiveField(4)
  final double pointsRedeemed;

  @HiveField(5)
  final String redemptionType; // 'statement_credit', 'voucher', 'cashback', 'transfer'

  @HiveField(6)
  final double redemptionValue; // Monetary value of redemption

  @HiveField(7)
  final String? voucherDetails; // If redeemed for voucher

  @HiveField(8)
  final String status; // 'pending', 'completed', 'failed'

  @HiveField(9)
  final DateTime redemptionDate;

  @HiveField(10)
  final DateTime? completedDate;

  @HiveField(11)
  final Map<String, dynamic> metadata;

  @HiveField(12)
  final DateTime createdAt;

  const RewardRedemption({
    required this.id,
    required this.userId,
    required this.userCardId,
    required this.rewardBalanceId,
    required this.pointsRedeemed,
    required this.redemptionType,
    required this.redemptionValue,
    this.voucherDetails,
    required this.status,
    required this.redemptionDate,
    this.completedDate,
    this.metadata = const {},
    required this.createdAt,
  });
  factory RewardRedemption.fromJson(Map<String, dynamic> json) {
    return RewardRedemption(
      id: json['id'],
      userId: json['user_id'],
      userCardId: json['user_card_id'],
      rewardBalanceId: json['reward_balance_id'],
      pointsRedeemed: (json['points_redeemed'] as num).toDouble(),
      redemptionType: json['redemption_type'],
      redemptionValue: (json['redemption_value'] as num).toDouble(),
      voucherDetails: json['voucher_details'],
      status: json['status'],
      redemptionDate: DateTime.parse(json['redemption_date']),
      completedDate: json['completed_date'] != null 
          ? DateTime.parse(json['completed_date'])
          : null,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_card_id': userCardId,
      'reward_balance_id': rewardBalanceId,
      'points_redeemed': pointsRedeemed,
      'redemption_type': redemptionType,
      'redemption_value': redemptionValue,
      'voucher_details': voucherDetails,
      'status': status,
      'redemption_date': redemptionDate.toIso8601String(),
      'completed_date': completedDate?.toIso8601String(),
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'RewardRedemption(id: $id, pointsRedeemed: $pointsRedeemed, redemptionType: $redemptionType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RewardRedemption && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
