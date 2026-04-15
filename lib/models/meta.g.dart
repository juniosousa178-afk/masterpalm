// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meta.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MetaAdapter extends TypeAdapter<Meta> {
  @override
  final int typeId = 16;

  @override
  Meta read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Meta(
      mesRef: fields[0] as String,
      metaMensal: fields[1] as double,
      crescimentoPercent: fields[2] as double,
      vendedorId: fields[3] as String,
      lojaId: fields[4] as String?,
      criadoEm: fields[5] as DateTime?,
      atualizadoEm: fields[6] as DateTime?,
      idFirebase: fields[7] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Meta obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.mesRef)
      ..writeByte(1)
      ..write(obj.metaMensal)
      ..writeByte(2)
      ..write(obj.crescimentoPercent)
      ..writeByte(3)
      ..write(obj.vendedorId)
      ..writeByte(4)
      ..write(obj.lojaId)
      ..writeByte(5)
      ..write(obj.criadoEm)
      ..writeByte(6)
      ..write(obj.atualizadoEm)
      ..writeByte(7)
      ..write(obj.idFirebase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MetaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
