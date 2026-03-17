// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fornecedor.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FornecedorAdapter extends TypeAdapter<Fornecedor> {
  @override
  final int typeId = 3;

  @override
  Fornecedor read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Fornecedor(
      nome: fields[0] as String,
      telefone: fields[1] as String,
      email: fields[2] as String,
      dataCadastro: fields[3] as DateTime?,
      instagram: fields[4] as String,
      whatsapp: fields[5] as String,
      linkInstagram: fields[6] as String,
      linkWhatsapp: fields[7] as String,
      lojaId: fields[8] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Fornecedor obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.telefone)
      ..writeByte(2)
      ..write(obj.email)
      ..writeByte(3)
      ..write(obj.dataCadastro)
      ..writeByte(4)
      ..write(obj.instagram)
      ..writeByte(5)
      ..write(obj.whatsapp)
      ..writeByte(6)
      ..write(obj.linkInstagram)
      ..writeByte(7)
      ..write(obj.linkWhatsapp)
      ..writeByte(8)
      ..write(obj.lojaId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FornecedorAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
