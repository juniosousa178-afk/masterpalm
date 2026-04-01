// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compra_fornecedor_item.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CompraFornecedorItemAdapter extends TypeAdapter<CompraFornecedorItem> {
  @override
  final int typeId = 33;

  @override
  CompraFornecedorItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CompraFornecedorItem(
      produtoNome: fields[0] as String,
      quantidade: fields[1] as int,
      custoUnitario: fields[2] as double,
      productId: fields[3] as String?,
      itemCompraId: fields[4] == null ? '' : fields[4] as String,
      codigoInterno: fields[5] == null ? '' : fields[5] as String,
      codigoBarras: fields[6] == null ? '' : fields[6] as String,
      observacaoItem: fields[7] == null ? '' : fields[7] as String,
      unidade: fields[8] == null ? '' : fields[8] as String,
      subtotalBase: fields[9] == null ? 0.0 : fields[9] as double,
      percentualParticipacao: fields[10] == null ? 0.0 : fields[10] as double,
      freteRateado: fields[11] == null ? 0.0 : fields[11] as double,
      descontoRateado: fields[12] == null ? 0.0 : fields[12] as double,
      outrasDespesasRateadas: fields[13] == null ? 0.0 : fields[13] as double,
      custoUnitarioFinal: fields[14] == null ? 0.0 : fields[14] as double,
      subtotalFinal: fields[15] == null ? 0.0 : fields[15] as double,
    );
  }

  @override
  void write(BinaryWriter writer, CompraFornecedorItem obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.produtoNome)
      ..writeByte(1)
      ..write(obj.quantidade)
      ..writeByte(2)
      ..write(obj.custoUnitario)
      ..writeByte(3)
      ..write(obj.productId)
      ..writeByte(4)
      ..write(obj.itemCompraId)
      ..writeByte(5)
      ..write(obj.codigoInterno)
      ..writeByte(6)
      ..write(obj.codigoBarras)
      ..writeByte(7)
      ..write(obj.observacaoItem)
      ..writeByte(8)
      ..write(obj.unidade)
      ..writeByte(9)
      ..write(obj.subtotalBase)
      ..writeByte(10)
      ..write(obj.percentualParticipacao)
      ..writeByte(11)
      ..write(obj.freteRateado)
      ..writeByte(12)
      ..write(obj.descontoRateado)
      ..writeByte(13)
      ..write(obj.outrasDespesasRateadas)
      ..writeByte(14)
      ..write(obj.custoUnitarioFinal)
      ..writeByte(15)
      ..write(obj.subtotalFinal);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompraFornecedorItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
