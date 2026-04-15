// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cliente.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ClienteAdapter extends TypeAdapter<Cliente> {
  @override
  final int typeId = 0;

  @override
  Cliente read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Cliente(
      nome: fields[0] as String,
      telefone: fields[1] as String,
      instagram: fields[2] as String,
      cep: fields[3] as String,
      cidade: fields[4] as String,
      historico: (fields[5] as HiveList?)?.castHiveList(),
      avatarPath: fields[6] as String?,
      email: fields[7] as String?,
      endereco: fields[8] as String?,
      lojaId: fields[9] as String,
      idFirebase: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Cliente obj) {
    writer
      ..writeByte(11)
      ..writeByte(6)
      ..write(obj.avatarPath)
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.telefone)
      ..writeByte(2)
      ..write(obj.instagram)
      ..writeByte(3)
      ..write(obj.cep)
      ..writeByte(4)
      ..write(obj.cidade)
      ..writeByte(5)
      ..write(obj.historico)
      ..writeByte(7)
      ..write(obj.email)
      ..writeByte(8)
      ..write(obj.endereco)
      ..writeByte(9)
      ..write(obj.lojaId)
      ..writeByte(10)
      ..write(obj.idFirebase);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClienteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
