// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'estoque_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EstoqueItemAdapter extends TypeAdapter<EstoqueItem> {
  @override
  final int typeId = 18;

  @override
  EstoqueItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EstoqueItem(
      nome: fields[0] as String,
      quantidade: fields[1] as int,
      precoUnitario: fields[2] as double,
      categoria: fields[3] as String,
      codigoBarras: fields[4] as String,
      dataEntrada: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, EstoqueItem obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.quantidade)
      ..writeByte(2)
      ..write(obj.precoUnitario)
      ..writeByte(3)
      ..write(obj.categoria)
      ..writeByte(4)
      ..write(obj.codigoBarras)
      ..writeByte(5)
      ..write(obj.dataEntrada);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EstoqueItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
