// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_card.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserCardAdapter extends TypeAdapter<UserCard> {
  @override
  final int typeId = 6;

  @override
  UserCard read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserCard(
      id: fields[0] as String,
      userId: fields[1] as String,
      catalogCardId: fields[2] as String,
      lastFourDigits: fields[3] as String?,
      cardNumber: fields[4] as String?,
      expiryDate: fields[5] as String?,
      cardHolderName: fields[6] as String?,
      creditLimit: fields[7] as double?,
      statementDate: fields[8] as int?,
      dueDate: fields[9] as int?,
      isActive: fields[10] as bool,
      createdAt: fields[11] as DateTime,
      updatedAt: fields[12] as DateTime,
      cardCatalog: fields[13] as CardCatalog?,
    );
  }

  @override
  void write(BinaryWriter writer, UserCard obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.userId)
      ..writeByte(2)
      ..write(obj.catalogCardId)
      ..writeByte(3)
      ..write(obj.lastFourDigits)
      ..writeByte(4)
      ..write(obj.cardNumber)
      ..writeByte(5)
      ..write(obj.expiryDate)
      ..writeByte(6)
      ..write(obj.cardHolderName)
      ..writeByte(7)
      ..write(obj.creditLimit)
      ..writeByte(8)
      ..write(obj.statementDate)
      ..writeByte(9)
      ..write(obj.dueDate)
      ..writeByte(10)
      ..write(obj.isActive)
      ..writeByte(11)
      ..write(obj.createdAt)
      ..writeByte(12)
      ..write(obj.updatedAt)
      ..writeByte(13)
      ..write(obj.cardCatalog);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserCardAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************


