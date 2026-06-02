// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conta_receber.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ContaReceberAdapter extends TypeAdapter<ContaReceber> {
  @override
  final int typeId = 29;

  @override
  ContaReceber read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContaReceber(
      lojaId: fields[0] as String,
      clienteNome: fields[1] as String,
      valor: fields[2] as double,
      dataVencimento: fields[3] as DateTime,
      dataVenda: fields[4] as DateTime,
      pago: fields[5] as bool,
      observacao: fields[6] as String,
      vendaKey: fields[7] as int,
      idFirebase: fields[8] as String?,
      parcelaNumero: fields[9] as int,
      parcelaTotal: fields[10] as int,
      lembrete2DiasEnviado: fields[11] as bool,
      valorOriginal: fields[12] as double?,
      valorPago: (fields[13] as double?) ?? 0,
      status: fields[14] as String?,
      historicoPagamentosJson: (fields[15] as String?) ?? '[]',
    );
  }

  @override
  void write(BinaryWriter writer, ContaReceber obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.lojaId)
      ..writeByte(1)
      ..write(obj.clienteNome)
      ..writeByte(2)
      ..write(obj.valor)
      ..writeByte(3)
      ..write(obj.dataVencimento)
      ..writeByte(4)
      ..write(obj.dataVenda)
      ..writeByte(5)
      ..write(obj.pago)
      ..writeByte(6)
      ..write(obj.observacao)
      ..writeByte(7)
      ..write(obj.vendaKey)
      ..writeByte(8)
      ..write(obj.idFirebase)
      ..writeByte(9)
      ..write(obj.parcelaNumero)
      ..writeByte(10)
      ..write(obj.parcelaTotal)
      ..writeByte(11)
      ..write(obj.lembrete2DiasEnviado)
      ..writeByte(12)
      ..write(obj.valorOriginal)
      ..writeByte(13)
      ..write(obj.valorPago)
      ..writeByte(14)
      ..write(obj.status)
      ..writeByte(15)
      ..write(obj.historicoPagamentosJson);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContaReceberAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
