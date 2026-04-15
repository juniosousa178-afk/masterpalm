// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subcategoria.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SubcategoriaAdapter extends TypeAdapter<Subcategoria> {
  @override
  final int typeId = 13;

  @override
  Subcategoria read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Subcategoria(
      nome: fields[0] as String,
      categoriaId: fields[1] as String,
      icone: fields[2] as String?,
      ativa: fields[3] as bool,
      dataCriacao: fields[4] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Subcategoria obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.categoriaId)
      ..writeByte(2)
      ..write(obj.icone)
      ..writeByte(3)
      ..write(obj.ativa)
      ..writeByte(4)
      ..write(obj.dataCriacao);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubcategoriaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
