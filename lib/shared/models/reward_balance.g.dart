// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reward_balance.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RewardBalanceAdapter extends TypeAdapter<RewardBalance> {
  @override
  final int typeId = 7;

  @override
  RewardBalance read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RewardBalance(
      id: fields[0] as String,
      userId: fields[1] as String,
      userCardId: fields[2] as String,
      rewardType: fields[3] as String,
      availableBalance: fields[4] as double,
      totalEarned: fields[5] as double,
      totalRedeemed: fields[6] as double,
      pendingBalance: fields[7] as double,
      expiryDate: fields[8] as DateTime?,
      metadata: (fields[9] as Map).cast<String, dynamic>(),
      lastUpdated: fields[10] as DateTime,
      createdAt: fields[11] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RewardBalance obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.userCardId)
      ..writeByte(3)
      ..write(obj.rewardType)
      ..writeByte(4)
      ..write(obj.availableBalance)
      ..writeByte(5)
      ..write(obj.totalEarned)
      ..writeByte(6)
      ..write(obj.totalRedeemed)
      ..writeByte(7)
      ..write(obj.pendingBalance)
      ..writeByte(8)
      ..write(obj.expiryDate)
      ..writeByte(9)
      ..write(obj.metadata)
      ..writeByte(10)
      ..write(obj.lastUpdated)
      ..writeByte(11)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardBalanceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RewardRedemptionAdapter extends TypeAdapter<RewardRedemption> {
  @override
  final int typeId = 8;

  @override
  RewardRedemption read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RewardRedemption(
      id: fields[0] as String,
      userId: fields[1] as String,
      userCardId: fields[2] as String,
      rewardBalanceId: fields[3] as String,
      pointsRedeemed: fields[4] as double,
      redemptionType: fields[5] as String,
      redemptionValue: fields[6] as double,
      voucherDetails: fields[7] as String?,
      status: fields[8] as String,
      redemptionDate: fields[9] as DateTime,
      completedDate: fields[10] as DateTime?,
      metadata: (fields[11] as Map).cast<String, dynamic>(),
      createdAt: fields[12] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, RewardRedemption obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.userCardId)
      ..writeByte(3)
      ..write(obj.rewardBalanceId)
      ..writeByte(4)
      ..write(obj.pointsRedeemed)
      ..writeByte(5)
      ..write(obj.redemptionType)
      ..writeByte(6)
      ..write(obj.redemptionValue)
      ..writeByte(7)
      ..write(obj.voucherDetails)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.redemptionDate)
      ..writeByte(10)
      ..write(obj.completedDate)
      ..writeByte(11)
      ..write(obj.metadata)
      ..writeByte(12)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RewardRedemptionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

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
