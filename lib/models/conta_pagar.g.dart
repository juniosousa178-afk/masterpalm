// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conta_pagar.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ContaPagarAdapter extends TypeAdapter<ContaPagar> {
  @override
  final int typeId = 35;

  @override
  ContaPagar read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContaPagar(
      id: fields[0] as String,
      lojaId: fields[1] as String,
      fornecedorId: fields[2] as int,
      fornecedorNome: fields[3] as String,
      compraId: fields[4] as String,
      descricao: fields[5] as String,
      valorTotalCompra: fields[6] as double,
      valorParcela: fields[7] as double,
      parcelaNumero: fields[8] as int,
      parcelaTotal: fields[9] as int,
      dataVencimento: fields[10] as DateTime,
      dataPagamento: fields[11] as DateTime?,
      status: fields[12] as String,
      formaPagamento: fields[13] as String,
      observacao: fields[14] as String,
      lancamentoFinanceiroId: fields[15] == null ? '' : fields[15] as String,
      criadoEm: fields[16] as DateTime?,
      atualizadoEm: fields[17] as DateTime?,
      dataCompra: fields[18] as DateTime,
      idFirebase: fields[19] == null ? '' : fields[19] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ContaPagar obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.fornecedorId)
      ..writeByte(3)
      ..write(obj.fornecedorNome)
      ..writeByte(4)
      ..write(obj.compraId)
      ..writeByte(5)
      ..write(obj.descricao)
      ..writeByte(6)
      ..write(obj.valorTotalCompra)
      ..writeByte(7)
      ..write(obj.valorParcela)
      ..writeByte(8)
      ..write(obj.parcelaNumero)
      ..writeByte(9)
      ..write(obj.parcelaTotal)
      ..writeByte(10)
      ..write(obj.dataVencimento)
      ..writeByte(11)
      ..write(obj.dataPagamento)
      ..writeByte(12)
      ..write(obj.status)
      ..writeByte(13)
      ..write(obj.formaPagamento)
      ..writeByte(14)
      ..write(obj.observacao)
      ..writeByte(15)
      ..write(obj.lancamentoFinanceiroId)
      ..writeByte(16)
      ..write(obj.criadoEm)
      ..writeByte(17)
      ..write(obj.atualizadoEm)
      ..writeByte(18)
      ..write(obj.dataCompra)
      ..writeByte(19)
      ..write(obj.idFirebase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContaPagarAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
