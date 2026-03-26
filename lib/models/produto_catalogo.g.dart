// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'produto_catalogo.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProdutoCatalogoAdapter extends TypeAdapter<ProdutoCatalogo> {
  @override
  final int typeId = 5;

  @override
  ProdutoCatalogo read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProdutoCatalogo(
      nome: fields[0] as String,
      descricao: fields[1] as String?,
      sobre: fields[2] as String?,
      tamanhos: (fields[3] as List).cast<String>(),
      quantidade: fields[4] as int,
      precoFinal: fields[5] as double,
      precoUnitario: fields[6] as double,
      precoSugerido: fields[7] as double,
      custoReal: fields[8] as double,
      frete: fields[9] as double,
      gastosFixos: fields[10] as double,
      gastosVariaveis: fields[11] as double,
      categoria: fields[12] as String,
      subcategoria: fields[13] as String?,
      dataEntrada: fields[14] as DateTime,
      imagens: (fields[15] as List).cast<String>(),
      lojaId: fields[16] as String,
      cores: (fields[17] as List).cast<String>(),
      variacoes: (fields[18] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, ProdutoCatalogo obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.descricao)
      ..writeByte(2)
      ..write(obj.sobre)
      ..writeByte(3)
      ..write(obj.tamanhos)
      ..writeByte(4)
      ..write(obj.quantidade)
      ..writeByte(5)
      ..write(obj.precoFinal)
      ..writeByte(6)
      ..write(obj.precoUnitario)
      ..writeByte(7)
      ..write(obj.precoSugerido)
      ..writeByte(8)
      ..write(obj.custoReal)
      ..writeByte(9)
      ..write(obj.frete)
      ..writeByte(10)
      ..write(obj.gastosFixos)
      ..writeByte(11)
      ..write(obj.gastosVariaveis)
      ..writeByte(12)
      ..write(obj.categoria)
      ..writeByte(13)
      ..write(obj.subcategoria)
      ..writeByte(14)
      ..write(obj.dataEntrada)
      ..writeByte(15)
      ..write(obj.imagens)
      ..writeByte(16)
      ..write(obj.lojaId)
      ..writeByte(17)
      ..write(obj.cores)
      ..writeByte(18)
      ..write(obj.variacoes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProdutoCatalogoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
