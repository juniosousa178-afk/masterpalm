// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fechamento_mensal.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FechamentoMensalAdapter extends TypeAdapter<FechamentoMensal> {
  @override
  final int typeId = 8;

  @override
  FechamentoMensal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FechamentoMensal(
      ano: fields[0] as int,
      mes: fields[1] as int,
      totalDinheiro: fields[2] as double,
      totalPix: fields[3] as double,
      totalCartao: fields[4] as double,
      vendaTotal: fields[5] as double,
      custoTotal: fields[6] as double,
      taxasTotal: fields[7] as double,
      lucroTotal: fields[8] as double,
      fechadoEm: fields[9] as DateTime,
      lojaId: fields[10] as String,
    );
  }

  @override
  void write(BinaryWriter writer, FechamentoMensal obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.ano)
      ..writeByte(1)
      ..write(obj.mes)
      ..writeByte(2)
      ..write(obj.totalDinheiro)
      ..writeByte(3)
      ..write(obj.totalPix)
      ..writeByte(4)
      ..write(obj.totalCartao)
      ..writeByte(5)
      ..write(obj.vendaTotal)
      ..writeByte(6)
      ..write(obj.custoTotal)
      ..writeByte(7)
      ..write(obj.taxasTotal)
      ..writeByte(8)
      ..write(obj.lucroTotal)
      ..writeByte(9)
      ..write(obj.fechadoEm)
      ..writeByte(10)
      ..write(obj.lojaId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FechamentoMensalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
