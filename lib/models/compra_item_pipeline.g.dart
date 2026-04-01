// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compra_item_pipeline.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CompraItemPipelineAdapter extends TypeAdapter<CompraItemPipeline> {
  @override
  final int typeId = 34;

  @override
  CompraItemPipeline read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CompraItemPipeline(
      id: fields[0] as String,
      lojaId: fields[1] as String,
      compraId: fields[2] as String,
      itemCompraId: fields[3] as String,
      fornecedorNome: fields[4] as String,
      referenciaCompra: fields[5] as String,
      nomeProdutoProvisorio: fields[6] as String,
      quantidade: fields[7] as int,
      custoUnitario: fields[8] as double,
      codigoInterno: fields[9] as String,
      codigoBarras: fields[10] as String,
      observacaoItem: fields[11] as String,
      unidade: fields[12] as String,
      productIdFirebase: fields[13] as String?,
      estado: fields[14] as String,
      precoSugerido: fields[15] as double,
      precoFinal: fields[16] as double,
      precoPretendidoUsuario: fields[17] as double,
      produtoHiveKey: fields[18] as int?,
      produtoIdFirebaseGravado: fields[19] as String,
      atualizadoEm: fields[20] as DateTime?,
      // Registros antigos sem campo 21: compatível com Hive pré-campo.
      compraCanceladaAposConclusao: (fields[21] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, CompraItemPipeline obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.compraId)
      ..writeByte(3)
      ..write(obj.itemCompraId)
      ..writeByte(4)
      ..write(obj.fornecedorNome)
      ..writeByte(5)
      ..write(obj.referenciaCompra)
      ..writeByte(6)
      ..write(obj.nomeProdutoProvisorio)
      ..writeByte(7)
      ..write(obj.quantidade)
      ..writeByte(8)
      ..write(obj.custoUnitario)
      ..writeByte(9)
      ..write(obj.codigoInterno)
      ..writeByte(10)
      ..write(obj.codigoBarras)
      ..writeByte(11)
      ..write(obj.observacaoItem)
      ..writeByte(12)
      ..write(obj.unidade)
      ..writeByte(13)
      ..write(obj.productIdFirebase)
      ..writeByte(14)
      ..write(obj.estado)
      ..writeByte(15)
      ..write(obj.precoSugerido)
      ..writeByte(16)
      ..write(obj.precoFinal)
      ..writeByte(17)
      ..write(obj.precoPretendidoUsuario)
      ..writeByte(18)
      ..write(obj.produtoHiveKey)
      ..writeByte(19)
      ..write(obj.produtoIdFirebaseGravado)
      ..writeByte(20)
      ..write(obj.atualizadoEm)
      ..writeByte(21)
      ..write(obj.compraCanceladaAposConclusao);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompraItemPipelineAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
