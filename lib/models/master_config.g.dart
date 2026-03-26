// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MasterConfigAdapter extends TypeAdapter<MasterConfig> {
  @override
  final int typeId = 15;

  @override
  MasterConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MasterConfig(
      masterPassword: fields[0] as String,
      mercadoPagoAccessToken: fields[1] as String?,
      mercadoPagoPublicKey: fields[2] as String?,
      requirePlanForNewUsers: fields[3] as bool,
      usersWithUnlimitedAccess: (fields[4] as List?)?.cast<String>(),
      globalSettings: (fields[5] as Map?)?.cast<String, dynamic>(),
      lastUpdated: fields[6] as DateTime?,
      updatedBy: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MasterConfig obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.masterPassword)
      ..writeByte(1)
      ..write(obj.mercadoPagoAccessToken)
      ..writeByte(2)
      ..write(obj.mercadoPagoPublicKey)
      ..writeByte(3)
      ..write(obj.requirePlanForNewUsers)
      ..writeByte(4)
      ..write(obj.usersWithUnlimitedAccess)
      ..writeByte(5)
      ..write(obj.globalSettings)
      ..writeByte(6)
      ..write(obj.lastUpdated)
      ..writeByte(7)
      ..write(obj.updatedBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MasterConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
