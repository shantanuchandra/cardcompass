// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserAdapter extends TypeAdapter<User> {
  @override
  final int typeId = 0;

  @override
  User read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return User(
      id: fields[0] as String,
      email: fields[1] as String,
      name: fields[2] as String?,
      profileImage: fields[3] as String?,
      createdAt: fields[4] as DateTime,
      lastLoginAt: fields[5] as DateTime?,
      cardIds: (fields[6] as List).cast<String>(),
      preferences: (fields[7] as Map).cast<String, dynamic>(),
      isPremium: fields[8] as bool,
      fullName: fields[9] as String?,
      phoneNumber: fields[10] as String?,
      dateOfBirth: fields[11] as DateTime?,
      annualIncome: fields[12] as double?,
      creditScore: fields[13] as int?,
      occupation: fields[14] as String?,
      city: fields[15] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, User obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.email)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.profileImage)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.lastLoginAt)
      ..writeByte(6)
      ..write(obj.cardIds)
      ..writeByte(7)
      ..write(obj.preferences)
      ..writeByte(8)
      ..write(obj.isPremium)
      ..writeByte(9)
      ..write(obj.fullName)
      ..writeByte(10)
      ..write(obj.phoneNumber)
      ..writeByte(11)
      ..write(obj.dateOfBirth)
      ..writeByte(12)
      ..write(obj.annualIncome)
      ..writeByte(13)
      ..write(obj.creditScore)
      ..writeByte(14)
      ..write(obj.occupation)
      ..writeByte(15)
      ..write(obj.city);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      profileImage: json['profileImage'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastLoginAt: json['lastLoginAt'] == null
          ? null
          : DateTime.parse(json['lastLoginAt'] as String),
      cardIds: (json['cardIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      preferences: json['preferences'] as Map<String, dynamic>? ?? const {},
      isPremium: json['isPremium'] as bool? ?? false,
      fullName: json['fullName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      dateOfBirth: json['dateOfBirth'] == null
          ? null
          : DateTime.parse(json['dateOfBirth'] as String),
      annualIncome: (json['annualIncome'] as num?)?.toDouble(),
      creditScore: (json['creditScore'] as num?)?.toInt(),
      occupation: json['occupation'] as String?,
      city: json['city'] as String?,
    );

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'name': instance.name,
      'profileImage': instance.profileImage,
      'createdAt': instance.createdAt.toIso8601String(),
      'lastLoginAt': instance.lastLoginAt?.toIso8601String(),
      'cardIds': instance.cardIds,
      'preferences': instance.preferences,
      'isPremium': instance.isPremium,
      'fullName': instance.fullName,
      'phoneNumber': instance.phoneNumber,
      'dateOfBirth': instance.dateOfBirth?.toIso8601String(),
      'annualIncome': instance.annualIncome,
      'creditScore': instance.creditScore,
      'occupation': instance.occupation,
      'city': instance.city,
    };
