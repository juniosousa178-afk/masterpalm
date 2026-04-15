// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compra_fornecedor.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CompraFornecedorAdapter extends TypeAdapter<CompraFornecedor> {
  @override
  final int typeId = 32;

  @override
  CompraFornecedor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CompraFornecedor(
      id: fields[0] as String,
      lojaId: fields[1] as String,
      fornecedorHiveKey: fields[2] as int,
      fornecedorNome: fields[3] as String,
      referenciaInterna: fields[4] as String,
      dataCompra: fields[5] as DateTime,
      dataVencimento: fields[6] as DateTime?,
      statusCompra: fields[7] as String,
      statusPagamento: fields[8] as String,
      observacao: fields[9] as String,
      frete: fields[10] as double,
      desconto: fields[11] as double,
      valorPago: fields[12] as double,
      itens: (fields[13] as List?)?.cast<CompraFornecedorItem>(),
      estoqueIntegrado: fields[14] == null ? false : fields[14] as bool,
      idLancamentoFinanceiro: fields[15] == null ? '' : fields[15] as String,
      confirmadoEm: fields[16] as DateTime?,
      criadoEm: fields[17] as DateTime?,
      atualizadoEm: fields[18] as DateTime?,
      outrasDespesas: fields[19] == null ? 0.0 : fields[19] as double,
      syncPendente: fields[20] == null ? true : fields[20] as bool,
      syncStatus: fields[21] == null ? 'pendente' : fields[21] as String,
    );
  }

  @override
  void write(BinaryWriter writer, CompraFornecedor obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.fornecedorHiveKey)
      ..writeByte(3)
      ..write(obj.fornecedorNome)
      ..writeByte(4)
      ..write(obj.referenciaInterna)
      ..writeByte(5)
      ..write(obj.dataCompra)
      ..writeByte(6)
      ..write(obj.dataVencimento)
      ..writeByte(7)
      ..write(obj.statusCompra)
      ..writeByte(8)
      ..write(obj.statusPagamento)
      ..writeByte(9)
      ..write(obj.observacao)
      ..writeByte(10)
      ..write(obj.frete)
      ..writeByte(11)
      ..write(obj.desconto)
      ..writeByte(12)
      ..write(obj.valorPago)
      ..writeByte(13)
      ..write(obj.itens)
      ..writeByte(14)
      ..write(obj.estoqueIntegrado)
      ..writeByte(15)
      ..write(obj.idLancamentoFinanceiro)
      ..writeByte(16)
      ..write(obj.confirmadoEm)
      ..writeByte(17)
      ..write(obj.criadoEm)
      ..writeByte(18)
      ..write(obj.atualizadoEm)
      ..writeByte(19)
      ..write(obj.outrasDespesas)
      ..writeByte(20)
      ..write(obj.syncPendente)
      ..writeByte(21)
      ..write(obj.syncStatus);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompraFornecedorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
