// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'venda_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class VendaItemAdapter extends TypeAdapter<VendaItem> {
  @override
  final int typeId = 7;

  @override
  VendaItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VendaItem(
      produtoNome: fields[0] as String,
      quantidade: fields[1] as int,
      precoUnitario: fields[2] as double,
      tamanho: fields[3] as String,
      lojaId: fields[4] as String,
      cor: fields[5] as String,
      productId: fields[6] as String?,
      variacaoExtraResumo: fields[7] == null ? '' : fields[7] as String,
      extraValor: fields[8] == null ? '' : fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, VendaItem obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.produtoNome)
      ..writeByte(1)
      ..write(obj.quantidade)
      ..writeByte(2)
      ..write(obj.precoUnitario)
      ..writeByte(3)
      ..write(obj.tamanho)
      ..writeByte(4)
      ..write(obj.lojaId)
      ..writeByte(5)
      ..write(obj.cor)
      ..writeByte(6)
      ..write(obj.productId)
      ..writeByte(7)
      ..write(obj.variacaoExtraResumo)
      ..writeByte(8)
      ..write(obj.extraValor);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VendaItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
