// lib/services/produto_upsert_service.dart
// Serviço de upsert para evitar duplicação de produtos no estoque.
// Chave única: (a) código de barras, (b) SKU, (c) nome normalizado + categoria.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/combo_config_canonical.dart';
import '../core/logger.dart';
import '../models/produto.dart';
import 'combo_receita_normalizacao.dart';

/// Normaliza string para comparação: remove acentos, lowercase, trim, colapsa espaços.
String normalizeKey(String s) {
  if (s.isEmpty) return '';
  const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  var out = s.toLowerCase().trim();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Busca produto existente pela chave única (barcode > sku > nome+categoria).
/// Quando categoria está vazia na importação, também tenta match apenas por nome
/// (evita duplicar quando Excel não tem coluna categoria e o produto já tem categoria).
Produto? findProdutoExistente(
  Box<Produto> box,
  String lojaId, {
  String? codigoBarras,
  String? sku,
  required String nome,
  String categoria = '',
}) {
  final nomeNorm = nome.trim();
  final catNorm = categoria.trim();
  final keyNomeCat = normalizeKey('$nomeNorm|$catNorm');
  final keyNomeOnly = normalizeKey(nomeNorm);

  if (keyNomeOnly.isEmpty) return null;

  Produto? porNomeCat;

  for (final p in box.values) {
    if (p.lojaId != lojaId) continue;

    final pKey = normalizeKey('${p.nome}|${p.categoria}');
    final pKeyNomeOnly = normalizeKey(p.nome);

    // a) Código de barras: slug pode armazenar barcode quando importado com coluna codigo_barras
    if (codigoBarras != null && codigoBarras.trim().isNotEmpty) {
      final b = codigoBarras.trim();
      if (p.slug == b || p.slug == '$lojaId-$b') return p;
    }

    // b) SKU: slug pode armazenar sku
    if (sku != null && sku.trim().isNotEmpty) {
      final s = sku.trim();
      if (p.slug == s || p.slug == '$lojaId-$s') return p;
    }

    // c) Fallback: nome + categoria (exato) ou apenas nome quando categoria vazia
    if (pKey == keyNomeCat) {
      porNomeCat ??= p;
    } else if (catNorm.isEmpty && pKeyNomeOnly == keyNomeOnly) {
      // Import sem categoria: atualiza produto existente com mesmo nome
      porNomeCat ??= p;
    }
  }

  return porNomeCat;
}

/// Detecta conflito: mesmo nome (ou nome+categoria), mas códigos diferentes.
/// Quando categoria é vazia, considera match por nome apenas.
bool hasConflito(
  Box<Produto> box,
  String lojaId,
  String nome,
  String categoria, {
  String? codigoBarras,
  String? sku,
}) {
  final key = normalizeKey('$nome|${categoria.trim()}');
  final keyNomeOnly = normalizeKey(nome.trim());
  if (keyNomeOnly.isEmpty) return false;

  for (final p in box.values) {
    if (p.lojaId != lojaId) continue;

    final pKey = normalizeKey('${p.nome}|${p.categoria}');
    final pKeyNomeOnly = normalizeKey(p.nome);

    final match = pKey == key ||
        (categoria.trim().isEmpty && pKeyNomeOnly == keyNomeOnly);
    if (!match) continue;

    final pSlug = p.slug.trim();
    if (codigoBarras != null && codigoBarras.trim().isNotEmpty) {
      final b = codigoBarras.trim();
      if (pSlug != b && pSlug != '$lojaId-$b') return true;
    }
    if (sku != null && sku.trim().isNotEmpty) {
      final s = sku.trim();
      if (pSlug != s && pSlug != '$lojaId-$s') return true;
    }
  }
  return false;
}

/// Resultado do upsert.
enum UpsertResult { inserted, updated, skippedConflict }

/// Resultado com o produto afetado (para sync).
typedef UpsertResultWithProduct = (UpsertResult, Produto?);

bool _temTexto(String? v) => v != null && v.trim().isNotEmpty;
bool _listaComDados(List<dynamic>? v) => v != null && v.isNotEmpty;
bool _mapaComDados(Map<dynamic, dynamic>? v) => v != null && v.isNotEmpty;

void _mergeProdutoExistente(Produto existente, Produto novo) {
  // Campos numéricos principais (importação traz valores concretos)
  existente.quantidade = novo.quantidade;
  if (existente.custoEditadoNoCadastro) {
    logW(
      '[CUSTO_GUARD] import merge: mantendo custoReal ${existente.custoReal} (cadastro manual)',
      tag: 'CUSTO_GUARD',
    );
  } else {
    existente.custoReal = novo.custoReal;
  }
  existente.precoFinal = novo.precoFinal;
  existente.precoUnitario = novo.precoUnitario;
  existente.precoSugerido = novo.precoSugerido;
  if (novo.frete > 0) existente.frete = novo.frete;
  if (novo.gastosFixos > 0) existente.gastosFixos = novo.gastosFixos;
  if (novo.gastosVariaveis > 0) existente.gastosVariaveis = novo.gastosVariaveis;
  if (novo.peso > 0) {
    existente.peso = novo.peso;
  } else if (novo.peso == 0 && existente.peso > 0) {
    logW(
      '[PESO_GUARD] import merge: mantendo peso ${existente.peso} g (import veio 0)',
      tag: 'PESO_GUARD',
    );
  }
  if (novo.estoqueMinimo > 0) existente.estoqueMinimo = novo.estoqueMinimo;

  // Texto/listas/mapas: só sobrescreve quando o novo trouxer dado válido.
  if (_temTexto(novo.nome)) existente.nome = novo.nome;
  if (_temTexto(novo.descricao)) existente.descricao = novo.descricao.trim();
  if (_temTexto(novo.categoria)) existente.categoria = novo.categoria.trim();
  if (_temTexto(novo.subcategoria)) existente.subcategoria = novo.subcategoria.trim();
  if (_listaComDados(novo.categoriasExtras)) {
    existente.categoriasExtras = List<String>.from(novo.categoriasExtras);
  }
  if (_listaComDados(novo.subcategoriasExtras)) {
    existente.subcategoriasExtras = List<String>.from(novo.subcategoriasExtras);
  }
  if (_temTexto(novo.codigoBarras)) existente.codigoBarras = novo.codigoBarras.trim();
  if (_temTexto(novo.videoUrl)) existente.videoUrl = novo.videoUrl.trim();
  if (_temTexto(novo.fornecedor)) existente.fornecedor = novo.fornecedor.trim();
  if (_temTexto(novo.lojaId)) existente.lojaId = novo.lojaId.trim();
  if (_temTexto(novo.slug)) existente.slug = novo.slug.trim();

  if (novo.publicadoNoCatalogo) {
    existente.publicadoNoCatalogo = true;
  }
  final trouxePromocao = novo.emPromocao ||
      novo.percentualPromo != null ||
      novo.valorPromo != null ||
      novo.dataInicioPromo != null ||
      novo.dataFimPromo != null;
  if (trouxePromocao) {
    existente.emPromocao = novo.emPromocao;
    existente.percentualPromo = novo.percentualPromo;
    existente.valorPromo = novo.valorPromo;
    existente.dataInicioPromo = novo.dataInicioPromo;
    existente.dataFimPromo = novo.dataFimPromo;
  }
  existente.tipoEmbalagem = _temTexto(novo.tipoEmbalagem)
      ? (novo.tipoEmbalagem == 'padrao'
          ? existente.tipoEmbalagem
          : novo.tipoEmbalagem)
      : existente.tipoEmbalagem;
  if (novo.divideSemJuros || novo.percentualDescontoPix > 0 || novo.maxParcelasSemJuros != 12) {
    existente.divideSemJuros = novo.divideSemJuros;
    existente.percentualDescontoPix = novo.percentualDescontoPix;
    existente.maxParcelasSemJuros = novo.maxParcelasSemJuros;
  }

  if (_listaComDados(novo.imagens)) {
    existente.imagens = List<String>.from(novo.imagens);
  }
  if (_listaComDados(novo.marketplaces)) {
    existente.marketplaces = List<String>.from(novo.marketplaces);
  }
  if (_listaComDados(novo.tamanhos)) {
    existente.tamanhos = List<String>.from(novo.tamanhos);
  }
  if (_listaComDados(novo.cores)) {
    existente.cores = List<String>.from(novo.cores);
  }

  if (_mapaComDados(novo.estoquePorTamanho)) {
    existente.estoquePorTamanho = Map<String, int>.from(novo.estoquePorTamanho);
  }
  if (ComboConfigCanonical.isEffective(novo.comboConfig)) {
    existente.comboConfig = ComboConfigCanonical.copyMap(novo.comboConfig);
  }
}

/// Upsert: atualiza se existir, insere se não existir.
/// Retorna (resultado, produto) para permitir sync no Firestore.
Future<UpsertResultWithProduct> upsertProduto(
  Box<Produto> box,
  String lojaId,
  Produto novo, {
  String? codigoBarras,
  String? sku,
  void Function(String msg)? onLog,
}) async {
  final codigoBarrasStr = codigoBarras?.trim();
  final skuStr = sku?.trim();

  if (hasConflito(box, lojaId, novo.nome, novo.categoria,
      codigoBarras: codigoBarrasStr, sku: skuStr)) {
    onLog?.call(
      'Conflito: produto "${novo.nome}" já existe com código diferente. Mantido separado.',
    );
    debugPrint(
      '[ProdutoUpsert] Conflito: ${novo.nome} (${novo.categoria}) - códigos diferentes',
    );
    return (UpsertResult.skippedConflict, null);
  }

  final existente = findProdutoExistente(
    box,
    lojaId,
    codigoBarras: codigoBarrasStr, sku: skuStr,
    nome: novo.nome,
    categoria: novo.categoria,
  );

  if (existente != null) {
    if (existente.key == null) {
      onLog?.call('Erro: produto existente sem key');
      return (UpsertResult.skippedConflict, null);
    }

    _mergeProdutoExistente(existente, novo);

    if (novo.precoPorTamanho != null && novo.precoPorTamanho!.isNotEmpty) {
      existente.precoPorTamanho = Map<String, double>.from(novo.precoPorTamanho!);
    }
    if (_temTexto(novo.tipoProduto)) {
      existente.tipoProduto = novo.tipoProduto;
    }
    if (novo.itensCombo != null && novo.itensCombo!.isNotEmpty) {
      final raw = novo.itensCombo!.map((m) => Map<String, dynamic>.from(m)).toList();
      final lojaProds = box.values.where((p) => p.lojaId == lojaId);
      existente.itensCombo =
          ComboReceitaNormalizacao.normalizeLista(raw, lojaProds);
    }

    if (novo.variacoes != null) {
      if (novo.variacoes!.isEmpty) {
        // Mapa vazio explícito = intenção de limpar (import/upsert futuro).
        logW(
          '[VARIACAO_CLEAR] import merge: variacoes mapa vazio → limpando variações e extras',
          tag: 'VARIACAO_CLEAR',
        );
        existente.variacoes = null;
        existente.variacoesExtraTipo = null;
        existente.estoquePorTamanho = _mapaComDados(novo.estoquePorTamanho)
            ? Map<String, int>.from(novo.estoquePorTamanho)
            : <String, int>{};
        existente.quantidade = novo.quantidade;
      } else {
        // Substitui totalmente as variações anteriores pelo mapa novo (cópia profunda),
        // evitando "misturar" tamanhos/cores de produtos diferentes.
        final Map<String, dynamic> deepCopy = {};
        for (final entry in novo.variacoes!.entries) {
          final key = entry.key;
          final value = entry.value;
          if (value is Map) {
            deepCopy[key] =
                Map<String, dynamic>.from(value.map((k, v) => MapEntry(k.toString(), v)));
          } else {
            deepCopy[key] = value;
          }
        }
        existente.variacoes = deepCopy;
        existente.recalcularQuantidadeTotal();
      }
    } else if (novo.estoquePorTamanho.isNotEmpty) {
      // Sem variacoes no payload (null = não informado), usa grade por tamanho quando veio no import.
      existente.quantidade =
          existente.estoquePorTamanho.values.fold(0, (a, b) => a + b);
    }

    // Atualizar slug apenas se não tiver código e o existente tiver
    if (codigoBarrasStr != null && codigoBarrasStr.isNotEmpty) {
      existente.slug = codigoBarrasStr;
    } else if (skuStr != null && skuStr.isNotEmpty) {
      existente.slug = existente.slug.isEmpty ? skuStr : existente.slug;
    }

    existente.custoEditadoNoCadastro = true;
    existente.updatedAt = DateTime.now();
    await existente.save();
    if (kDebugMode) {
      debugPrint('[ProdutoImport] merge atualizado: ${existente.nome}');
    }
    onLog?.call('Atualizado: ${existente.nome}');
    return (UpsertResult.updated, existente);
  }

  final slugFinal = codigoBarrasStr;
  if (slugFinal != null && slugFinal.isNotEmpty) {
    novo.slug = slugFinal;
  } else if (skuStr != null && skuStr.isNotEmpty) {
    novo.slug = skuStr;
  } else if (novo.slug.isEmpty) {
    novo.slug = '$lojaId-${_slugify(novo.nome)}';
  }

  novo.custoEditadoNoCadastro = true;
  novo.updatedAt = DateTime.now();
  await box.add(novo);
  await novo.save();
  onLog?.call('Inserido: ${novo.nome}');
  return (UpsertResult.inserted, novo);
}

String _slugify(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
