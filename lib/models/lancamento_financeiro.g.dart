// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lancamento_financeiro.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LancamentoFinanceiroAdapter extends TypeAdapter<LancamentoFinanceiro> {
  @override
  final int typeId = 30;

  @override
  LancamentoFinanceiro read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LancamentoFinanceiro(
      id: fields[0] as String,
      lojaId: fields[1] as String,
      descricao: fields[2] as String,
      valor: fields[3] as double,
      tipo: fields[4] as String,
      categoria: fields[5] as String,
      subcategoria: fields[6] as String,
      status: fields[7] as String,
      formaPagamento: fields[8] as String,
      fornecedor: fields[9] as String,
      observacao: fields[10] as String,
      dataLancamento: fields[11] as DateTime,
      dataPagamento: fields[12] as DateTime?,
      competenciaMes: fields[13] as int?,
      competenciaAno: fields[14] as int?,
      recorrente: fields[15] as bool,
      origem: fields[16] as String,
      usuarioId: fields[17] as String,
      usuarioNome: fields[18] as String,
      centroCusto: fields[19] as String,
      anexoComprovante: fields[20] as String,
      referenciaExterna: fields[21] == null ? '' : fields[21] as String,
      solicitarAtualizacaoEstoque:
          fields[22] == null ? false : fields[22] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LancamentoFinanceiro obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.descricao)
      ..writeByte(3)
      ..write(obj.valor)
      ..writeByte(4)
      ..write(obj.tipo)
      ..writeByte(5)
      ..write(obj.categoria)
      ..writeByte(6)
      ..write(obj.subcategoria)
      ..writeByte(7)
      ..write(obj.status)
      ..writeByte(8)
      ..write(obj.formaPagamento)
      ..writeByte(9)
      ..write(obj.fornecedor)
      ..writeByte(10)
      ..write(obj.observacao)
      ..writeByte(11)
      ..write(obj.dataLancamento)
      ..writeByte(12)
      ..write(obj.dataPagamento)
      ..writeByte(13)
      ..write(obj.competenciaMes)
      ..writeByte(14)
      ..write(obj.competenciaAno)
      ..writeByte(15)
      ..write(obj.recorrente)
      ..writeByte(16)
      ..write(obj.origem)
      ..writeByte(17)
      ..write(obj.usuarioId)
      ..writeByte(18)
      ..write(obj.usuarioNome)
      ..writeByte(19)
      ..write(obj.centroCusto)
      ..writeByte(20)
      ..write(obj.anexoComprovante)
      ..writeByte(21)
      ..write(obj.referenciaExterna)
      ..writeByte(22)
      ..write(obj.solicitarAtualizacaoEstoque);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LancamentoFinanceiroAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
