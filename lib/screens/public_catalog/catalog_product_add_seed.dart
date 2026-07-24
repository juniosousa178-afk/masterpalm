// Snapshot imutável capturado ao abrir o modal de seleção no card do catálogo.
// Evita leitura tardia de props mutáveis do widget enquanto o sheet permanece aberto.

import 'package:flutter/foundation.dart';

Map<String, int> catalogProductAddSeedCopyIntMap(Map<String, int>? source) {
  if (source == null || source.isEmpty) return const {};
  return Map<String, int>.from(source);
}

Map<String, double>? catalogProductAddSeedCopyDoubleMap(
  Map<String, double>? source,
) {
  if (source == null || source.isEmpty) return null;
  return Map<String, double>.from(source);
}

dynamic catalogProductAddSeedDeepCopyValue(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key, catalogProductAddSeedDeepCopyValue(nested)),
    );
  }
  if (value is List) {
    return value.map(catalogProductAddSeedDeepCopyValue).toList();
  }
  return value;
}

Map<String, dynamic>? catalogProductAddSeedCopyDynamicMap(
  Map<String, dynamic>? source,
) {
  if (source == null || source.isEmpty) return null;
  return Map<String, dynamic>.from(
    source.map(
      (key, value) => MapEntry(key, catalogProductAddSeedDeepCopyValue(value)),
    ),
  );
}

List<String> catalogProductAddSeedCopyStringList(List<String> source) {
  return List<String>.from(source);
}

/// Campos congelados uma única vez antes de [showModalBottomSheet].
@immutable
class CatalogProductAddSeed {
  const CatalogProductAddSeed({
    required this.productId,
    required this.name,
    required this.price,
    required this.slug,
    required this.percentualDescontoPix,
    required this.divideSemJuros,
    required this.maxParcelas,
    required this.peso,
    required this.tipoEmbalagem,
    required this.imagens,
    required this.imageUrl,
    required this.minimalLayout,
    required this.emPromocao,
    required this.mostrarQuantidadeNoCatalogo,
    required this.estoquePorTamanho,
    required this.estoquePorCor,
    this.precoOriginal,
    this.precoPorTamanho,
    this.variacoes,
    this.variacoesExtraTipo,
    this.initialExtraValor,
    this.onCatalogVariacaoExtraChanged,
  });

  final String productId;
  final String name;
  final double price;
  final String slug;
  final double percentualDescontoPix;
  final bool divideSemJuros;
  final int maxParcelas;
  final double peso;
  final String tipoEmbalagem;
  final List<String> imagens;
  final String imageUrl;
  final bool minimalLayout;
  final bool emPromocao;
  final bool mostrarQuantidadeNoCatalogo;
  final Map<String, int> estoquePorTamanho;
  final Map<String, int> estoquePorCor;
  final double? precoOriginal;
  final Map<String, double>? precoPorTamanho;
  final Map<String, dynamic>? variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final String? initialExtraValor;
  final void Function(String? value)? onCatalogVariacaoExtraChanged;

  String get primaryImage =>
      imagens.isNotEmpty ? imagens.first : imageUrl;

  /// Linha enviada ao carrinho a partir da seleção confirmada no sheet.
  Map<String, dynamic> buildCartLine({
    required String? tamanho,
    required String? cor,
    required num preco,
    required String extraValor,
    required String extraTipo,
    required String resumoExtra,
  }) {
    final img = primaryImage;
    final ex = extraValor.trim();
    return {
      'produtosId': productId,
      'id': productId,
      'nome': name,
      'preco': preco,
      'percentualDescontoPix': percentualDescontoPix,
      'divideSemJuros': divideSemJuros,
      'maxParcelasSemJuros': maxParcelas,
      'quantidade': 1,
      'imageUrl': img,
      'url_foto': img,
      'slug': slug,
      'peso': peso,
      'tipoEmbalagem': tipoEmbalagem,
      'tamanho': tamanho ?? '',
      'cor': cor ?? '',
      if (ex.isNotEmpty) 'extraValor': ex,
      if (extraTipo.trim().isNotEmpty) 'extraTipo': extraTipo.trim(),
      if (resumoExtra.isNotEmpty) 'variacaoExtraResumo': resumoExtra,
    };
  }
}
