// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_catalog.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CardCatalogAdapter extends TypeAdapter<CardCatalog> {
  @override
  final int typeId = 5;

  @override
  CardCatalog read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CardCatalog(
      id: fields[0] as String,
      bank: fields[1] as String,
      cardName: fields[2] as String,
      network: fields[3] as String,
      cardType: fields[4] as String,
      joiningFee: fields[5] as double?,
      annualFee: fields[6] as double?,
      apr: fields[7] as double?,
      isDiscontinued: fields[8] as bool,
      createdAt: fields[9] as DateTime,
      updatedAt: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CardCatalog obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.bank)
      ..writeByte(2)
      ..write(obj.cardName)
      ..writeByte(3)
      ..write(obj.network)
      ..writeByte(4)
      ..write(obj.cardType)
      ..writeByte(5)
      ..write(obj.joiningFee)
      ..writeByte(6)
      ..write(obj.annualFee)
      ..writeByte(7)
      ..write(obj.apr)
      ..writeByte(8)
      ..write(obj.isDiscontinued)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardCatalogAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CardCatalog _$CardCatalogFromJson(Map<String, dynamic> json) => CardCatalog(
      id: json['id'] as String,
      bank: json['bank'] as String,
      cardName: json['cardName'] as String,
      network: json['network'] as String,
      cardType: json['cardType'] as String,
      joiningFee: (json['joiningFee'] as num?)?.toDouble(),
      annualFee: (json['annualFee'] as num?)?.toDouble(),
      apr: (json['apr'] as num?)?.toDouble(),
      isDiscontinued: json['isDiscontinued'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$CardCatalogToJson(CardCatalog instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bank': instance.bank,
      'cardName': instance.cardName,
      'network': instance.network,
      'cardType': instance.cardType,
      'joiningFee': instance.joiningFee,
      'annualFee': instance.annualFee,
      'apr': instance.apr,
      'isDiscontinued': instance.isDiscontinued,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
