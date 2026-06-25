// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'produto.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProdutoAdapter extends TypeAdapter<Produto> {
  @override
  final int typeId = 2;

  @override
  Produto read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Produto(
      nome: fields[0] as String,
      custoReal: fields[1] as double,
      frete: fields[2] as double,
      gastosFixos: fields[3] as double,
      gastosVariaveis: fields[4] as double,
      precoSugerido: fields[5] as double,
      precoFinal: fields[6] as double,
      quantidade: fields[7] as int,
      precoUnitario: fields[8] as double,
      categoria: fields[9] as String,
      dataEntrada: fields[10] as DateTime,
      descricao: fields[11] as String,
      imagens: (fields[12] as List).cast<String>(),
      publicadoNoCatalogo: fields[13] as bool,
      slug: fields[14] as String,
      tamanhos: (fields[15] as List).cast<String>(),
      subcategoria: fields[16] as String,
      estoquePorTamanho: (fields[17] as Map).cast<String, int>(),
      cores: (fields[28] as List).cast<String>(),
      ativoNoRascunho: fields[18] as bool,
      idFirebase: fields[19] as String,
      lojaId: fields[20] as String,
      emPromocao: fields[21] == null ? false : fields[21] as bool,
      percentualPromo: fields[22] as double?,
      valorPromo: fields[23] as double?,
      dataInicioPromo: fields[24] as DateTime?,
      dataFimPromo: fields[25] as DateTime?,
      peso: fields[26] == null ? 0.0 : fields[26] as double,
      tipoEmbalagem: fields[27] == null ? 'padrao' : fields[27] as String,
      marketplaces:
          fields[29] == null ? [] : (fields[29] as List).cast<String>(),
      variacoes: (fields[30] as Map?)?.cast<String, dynamic>(),
      variacoesExtraTipo: (fields[43] as Map?)?.cast<String, dynamic>(),
      divideSemJuros: fields[31] == null ? false : fields[31] as bool,
      percentualDescontoPix: fields[32] == null ? 0.0 : fields[32] as double,
      maxParcelasSemJuros: fields[33] == null ? 12 : fields[33] as int,
      videoUrl: fields[34] == null ? '' : fields[34] as String,
      codigoBarras: fields[35] == null ? '' : fields[35] as String,
      estoqueMinimo: fields[36] == null ? 0 : fields[36] as int,
      precoPorTamanho: (fields[37] as Map?)?.cast<String, double>(),
      tipoProduto: fields[38] == null ? 'simples' : fields[38] as String,
      itensCombo: (fields[39] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, dynamic>())
          ?.toList(),
      comboConfig: (fields[44] as Map?)?.cast<String, dynamic>(),
      updatedAt: fields[40] as DateTime?,
      custoEditadoNoCadastro: fields[41] == null ? false : fields[41] as bool,
      fornecedor: fields[42] == null ? '' : fields[42] as String,
      categoriasExtras:
          fields[45] == null ? [] : (fields[45] as List).cast<String>(),
      subcategoriasExtras:
          fields[46] == null ? [] : (fields[46] as List).cast<String>(),
      sku: fields[47] == null ? '' : fields[47] as String,
    );
  }

  @override
  void write(BinaryWriter writer, Produto obj) {
    writer
      ..writeByte(48)
      ..writeByte(0)
      ..write(obj.nome)
      ..writeByte(1)
      ..write(obj.custoReal)
      ..writeByte(2)
      ..write(obj.frete)
      ..writeByte(3)
      ..write(obj.gastosFixos)
      ..writeByte(4)
      ..write(obj.gastosVariaveis)
      ..writeByte(5)
      ..write(obj.precoSugerido)
      ..writeByte(6)
      ..write(obj.precoFinal)
      ..writeByte(7)
      ..write(obj.quantidade)
      ..writeByte(8)
      ..write(obj.precoUnitario)
      ..writeByte(9)
      ..write(obj.categoria)
      ..writeByte(10)
      ..write(obj.dataEntrada)
      ..writeByte(11)
      ..write(obj.descricao)
      ..writeByte(12)
      ..write(obj.imagens)
      ..writeByte(13)
      ..write(obj.publicadoNoCatalogo)
      ..writeByte(14)
      ..write(obj.slug)
      ..writeByte(15)
      ..write(obj.tamanhos)
      ..writeByte(16)
      ..write(obj.subcategoria)
      ..writeByte(17)
      ..write(obj.estoquePorTamanho)
      ..writeByte(28)
      ..write(obj.cores)
      ..writeByte(18)
      ..write(obj.ativoNoRascunho)
      ..writeByte(19)
      ..write(obj.idFirebase)
      ..writeByte(20)
      ..write(obj.lojaId)
      ..writeByte(21)
      ..write(obj.emPromocao)
      ..writeByte(22)
      ..write(obj.percentualPromo)
      ..writeByte(23)
      ..write(obj.valorPromo)
      ..writeByte(24)
      ..write(obj.dataInicioPromo)
      ..writeByte(25)
      ..write(obj.dataFimPromo)
      ..writeByte(26)
      ..write(obj.peso)
      ..writeByte(27)
      ..write(obj.tipoEmbalagem)
      ..writeByte(29)
      ..write(obj.marketplaces)
      ..writeByte(30)
      ..write(obj.variacoes)
      ..writeByte(43)
      ..write(obj.variacoesExtraTipo)
      ..writeByte(31)
      ..write(obj.divideSemJuros)
      ..writeByte(32)
      ..write(obj.percentualDescontoPix)
      ..writeByte(33)
      ..write(obj.maxParcelasSemJuros)
      ..writeByte(34)
      ..write(obj.videoUrl)
      ..writeByte(35)
      ..write(obj.codigoBarras)
      ..writeByte(36)
      ..write(obj.estoqueMinimo)
      ..writeByte(37)
      ..write(obj.precoPorTamanho)
      ..writeByte(38)
      ..write(obj.tipoProduto)
      ..writeByte(39)
      ..write(obj.itensCombo)
      ..writeByte(44)
      ..write(obj.comboConfig)
      ..writeByte(40)
      ..write(obj.updatedAt)
      ..writeByte(41)
      ..write(obj.custoEditadoNoCadastro)
      ..writeByte(42)
      ..write(obj.fornecedor)
      ..writeByte(45)
      ..write(obj.categoriasExtras)
      ..writeByte(46)
      ..write(obj.subcategoriasExtras)
      ..writeByte(47)
      ..write(obj.sku);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProdutoAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
