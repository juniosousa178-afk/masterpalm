// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'catalogo_config.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CatalogoConfigAdapter extends TypeAdapter<CatalogoConfig> {
  @override
  final int typeId = 6;

  @override
  CatalogoConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CatalogoConfig(
      corFundo: fields[0] as String,
      corTexto: fields[1] as String,
      corBotao: fields[2] as String,
      fonte: fields[3] as String,
      tamanhoFonte: fields[4] as double,
      corCabecalho: fields[5] as String,
    );
  }

  @override
  void write(BinaryWriter writer, CatalogoConfig obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.corFundo)
      ..writeByte(1)
      ..write(obj.corTexto)
      ..writeByte(2)
      ..write(obj.corBotao)
      ..writeByte(3)
      ..write(obj.fonte)
      ..writeByte(4)
      ..write(obj.tamanhoFonte)
      ..writeByte(5)
      ..write(obj.corCabecalho);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogoConfigAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
