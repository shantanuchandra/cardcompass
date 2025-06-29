// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_card.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CreditCardAdapter extends TypeAdapter<CreditCard> {
  @override
  final int typeId = 1;

  @override
  CreditCard read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CreditCard(
      id: fields[0] as String,
      userId: fields[1] as String,
      cardName: fields[2] as String,
      bankName: fields[3] as String,
      cardNumber: fields[4] as String?,
      network: fields[5] as CardNetwork,
      type: fields[6] as CardType,
      cardImage: fields[7] as String?,
      issuedDate: fields[8] as DateTime,
      expiryDate: fields[9] as DateTime?,
      annualFee: fields[10] as double?,
      creditLimit: fields[11] as double?,
      benefits: (fields[12] as List).cast<Benefit>(),
      rewardRates: (fields[13] as Map).cast<String, double>(),
      isActive: fields[14] as bool,
      createdAt: fields[15] as DateTime,
      updatedAt: fields[16] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CreditCard obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.cardName)
      ..writeByte(3)
      ..write(obj.bankName)
      ..writeByte(4)
      ..write(obj.cardNumber)
      ..writeByte(5)
      ..write(obj.network)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.cardImage)
      ..writeByte(8)
      ..write(obj.issuedDate)
      ..writeByte(9)
      ..write(obj.expiryDate)
      ..writeByte(10)
      ..write(obj.annualFee)
      ..writeByte(11)
      ..write(obj.creditLimit)
      ..writeByte(12)
      ..write(obj.benefits)
      ..writeByte(13)
      ..write(obj.rewardRates)
      ..writeByte(14)
      ..write(obj.isActive)
      ..writeByte(15)
      ..write(obj.createdAt)
      ..writeByte(16)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreditCardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class BenefitTypeAdapter extends TypeAdapter<BenefitType> {
  @override
  final int typeId = 3;

  @override
  BenefitType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return BenefitType.cashback;
      case 1:
        return BenefitType.rewardPoints;
      case 2:
        return BenefitType.discount;
      case 3:
        return BenefitType.freeService;
      case 4:
        return BenefitType.insurance;
      case 5:
        return BenefitType.loungeAccess;
      case 6:
        return BenefitType.fuelSurcharge;
      case 7:
        return BenefitType.emi;
      case 8:
        return BenefitType.other;
      default:
        return BenefitType.cashback;
    }
  }

  @override
  void write(BinaryWriter writer, BenefitType obj) {
    switch (obj) {
      case BenefitType.cashback:
        writer.writeByte(0);
        break;
      case BenefitType.rewardPoints:
        writer.writeByte(1);
        break;
      case BenefitType.discount:
        writer.writeByte(2);
        break;
      case BenefitType.freeService:
        writer.writeByte(3);
        break;
      case BenefitType.insurance:
        writer.writeByte(4);
        break;
      case BenefitType.loungeAccess:
        writer.writeByte(5);
        break;
      case BenefitType.fuelSurcharge:
        writer.writeByte(6);
        break;
      case BenefitType.emi:
        writer.writeByte(7);
        break;
      case BenefitType.other:
        writer.writeByte(8);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BenefitTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreditCard _$CreditCardFromJson(Map<String, dynamic> json) => CreditCard(
      id: json['id'] as String,
      userId: json['userId'] as String,
      cardName: json['cardName'] as String,
      bankName: json['bankName'] as String,
      cardNumber: json['cardNumber'] as String?,
      network: $enumDecode(_$CardNetworkEnumMap, json['network']),
      type: $enumDecode(_$CardTypeEnumMap, json['type']),
      cardImage: json['cardImage'] as String?,
      issuedDate: DateTime.parse(json['issuedDate'] as String),
      expiryDate: json['expiryDate'] == null
          ? null
          : DateTime.parse(json['expiryDate'] as String),
      annualFee: (json['annualFee'] as num?)?.toDouble(),
      creditLimit: (json['creditLimit'] as num?)?.toDouble(),
      benefits: (json['benefits'] as List<dynamic>?)
              ?.map((e) => Benefit.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      rewardRates: (json['rewardRates'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toDouble()),
          ) ??
          const {},
      isActive: json['isActive'] as bool? ?? true,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      catalogCardId: json['catalogCardId'] as String?,
    );

Map<String, dynamic> _$CreditCardToJson(CreditCard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'cardName': instance.cardName,
      'bankName': instance.bankName,
      'cardNumber': instance.cardNumber,
      'network': _$CardNetworkEnumMap[instance.network]!,
      'type': _$CardTypeEnumMap[instance.type]!,
      'cardImage': instance.cardImage,
      'issuedDate': instance.issuedDate.toIso8601String(),
      'expiryDate': instance.expiryDate?.toIso8601String(),
      'annualFee': instance.annualFee,
      'creditLimit': instance.creditLimit,
      'benefits': instance.benefits,
      'rewardRates': instance.rewardRates,
      'isActive': instance.isActive,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'catalogCardId': instance.catalogCardId,
    };

const _$CardNetworkEnumMap = {
  CardNetwork.visa: 'visa',
  CardNetwork.mastercard: 'mastercard',
  CardNetwork.rupay: 'rupay',
  CardNetwork.amex: 'amex',
  CardNetwork.discover: 'discover',
  CardNetwork.diners: 'diners',
};

const _$CardTypeEnumMap = {
  CardType.credit: 'credit',
  CardType.debit: 'debit',
  CardType.prepaid: 'prepaid',
};
