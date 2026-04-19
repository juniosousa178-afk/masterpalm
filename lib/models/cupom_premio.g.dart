// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cupom_premio.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CupomPremioAdapter extends TypeAdapter<CupomPremio> {
  @override
  final int typeId = 14;

  @override
  CupomPremio read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CupomPremio(
      codigo: fields[0] as String,
      tipo: fields[1] as String,
      valorDesconto: fields[2] as double,
      dataExpiracao: fields[3] as DateTime,
      usado: fields[4] as bool,
      dataUso: fields[5] as DateTime?,
      vendaId: fields[6] as String?,
      premioOriginal: fields[7] as String,
      lojaId: fields[8] as String,
      clienteEmail: fields[9] as String?,
      dataCriacao: fields[10] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, CupomPremio obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.codigo)
      ..writeByte(1)
      ..write(obj.tipo)
      ..writeByte(2)
      ..write(obj.valorDesconto)
      ..writeByte(3)
      ..write(obj.dataExpiracao)
      ..writeByte(4)
      ..write(obj.usado)
      ..writeByte(5)
      ..write(obj.dataUso)
      ..writeByte(6)
      ..write(obj.vendaId)
      ..writeByte(7)
      ..write(obj.premioOriginal)
      ..writeByte(8)
      ..write(obj.lojaId)
      ..writeByte(9)
      ..write(obj.clienteEmail)
      ..writeByte(10)
      ..write(obj.dataCriacao);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CupomPremioAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
