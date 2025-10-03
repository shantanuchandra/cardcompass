// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 4;

  @override
  Transaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Transaction(
      id: fields[0] as String,
      userId: fields[1] as String,
      userCardId: fields[17] as String?,
      amount: fields[3] as double,
      currency: fields[4] as String,
      description: fields[5] as String,
      merchantName: fields[6] as String?,
      category: fields[7] as TransactionCategory,
      type: fields[8] as TransactionType,
      transactionDate: fields[9] as DateTime,
      location: fields[10] as String?,
      rewardEarned: fields[11] as double?,
      rewardType: fields[12] as String?,
      metadata: (fields[13] as Map).cast<String, dynamic>(),
      statementId: fields[14] as String?,
      isRecurring: fields[15] as bool,
      createdAt: fields[16] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(17)
      ..write(obj.userCardId)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.currency)
      ..writeByte(5)
      ..write(obj.description)
      ..writeByte(6)
      ..write(obj.merchantName)
      ..writeByte(7)
      ..write(obj.category)
      ..writeByte(8)
      ..write(obj.type)
      ..writeByte(9)
      ..write(obj.transactionDate)
      ..writeByte(10)
      ..write(obj.location)
      ..writeByte(11)
      ..write(obj.rewardEarned)
      ..writeByte(12)
      ..write(obj.rewardType)
      ..writeByte(13)
      ..write(obj.metadata)
      ..writeByte(14)
      ..write(obj.statementId)
      ..writeByte(15)
      ..write(obj.isRecurring)
      ..writeByte(16)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************


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
