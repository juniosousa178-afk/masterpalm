// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gasto_fixo_mensal.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class GastoFixoMensalAdapter extends TypeAdapter<GastoFixoMensal> {
  @override
  final int typeId = 31;

  @override
  GastoFixoMensal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GastoFixoMensal(
      id: fields[0] as String,
      lojaId: fields[1] as String,
      descricao: fields[2] as String,
      valorPadrao: fields[3] as double,
      categoria: fields[4] as String,
      subcategoria: fields[5] as String,
      diaVencimento: fields[6] as int,
      ativo: fields[7] as bool,
      formaPagamentoPadrao: fields[8] as String,
      fornecedor: fields[9] as String,
      observacao: fields[10] as String,
      centroCusto: fields[11] as String,
    );
  }

  @override
  void write(BinaryWriter writer, GastoFixoMensal obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lojaId)
      ..writeByte(2)
      ..write(obj.descricao)
      ..writeByte(3)
      ..write(obj.valorPadrao)
      ..writeByte(4)
      ..write(obj.categoria)
      ..writeByte(5)
      ..write(obj.subcategoria)
      ..writeByte(6)
      ..write(obj.diaVencimento)
      ..writeByte(7)
      ..write(obj.ativo)
      ..writeByte(8)
      ..write(obj.formaPagamentoPadrao)
      ..writeByte(9)
      ..write(obj.fornecedor)
      ..writeByte(10)
      ..write(obj.observacao)
      ..writeByte(11)
      ..write(obj.centroCusto);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GastoFixoMensalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
