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
      estoqueEntradaRegistrada: fields[16] == null ? false : fields[16] as bool,
      estoqueSnapshotOk: fields[17] == null ? false : fields[17] as bool,
      estoqueAnterior: fields[18] == null ? 0 : fields[18] as int,
      custoAnterior: fields[19] == null ? 0.0 : fields[19] as double,
      tamanhoEntrada: fields[20] == null ? '' : fields[20] as String,
      corEntrada: fields[21] == null ? '' : fields[21] as String,
      produtoNovoNaCompra: fields[22] == null ? false : fields[22] as bool,
      custoEntradaRegistrado: fields[23] == null ? 0.0 : fields[23] as double,
    );
  }

  @override
  void write(BinaryWriter writer, CompraFornecedorItem obj) {
    writer
      ..writeByte(24)
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
      ..write(obj.subtotalFinal)
      ..writeByte(16)
      ..write(obj.estoqueEntradaRegistrada)
      ..writeByte(17)
      ..write(obj.estoqueSnapshotOk)
      ..writeByte(18)
      ..write(obj.estoqueAnterior)
      ..writeByte(19)
      ..write(obj.custoAnterior)
      ..writeByte(20)
      ..write(obj.tamanhoEntrada)
      ..writeByte(21)
      ..write(obj.corEntrada)
      ..writeByte(22)
      ..write(obj.produtoNovoNaCompra)
      ..writeByte(23)
      ..write(obj.custoEntradaRegistrado);
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
