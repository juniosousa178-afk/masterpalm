// lib/services/produto_upsert_service.dart
// Serviço de upsert para evitar duplicação de produtos no estoque.
// Chave única: (a) código de barras, (b) SKU, (c) nome normalizado + categoria.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/produto.dart';

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

    existente.quantidade = novo.quantidade;
    existente.custoReal = novo.custoReal;
    existente.precoFinal = novo.precoFinal;
    existente.precoUnitario = novo.precoUnitario;
    existente.precoSugerido = novo.precoSugerido;
    existente.estoquePorTamanho = Map<String, int>.from(novo.estoquePorTamanho);
    existente.tamanhos = List<String>.from(novo.tamanhos);
    existente.cores = List<String>.from(novo.cores);

    if (novo.precoPorTamanho != null && novo.precoPorTamanho!.isNotEmpty) {
      existente.precoPorTamanho = Map<String, double>.from(novo.precoPorTamanho!);
    } else {
      existente.precoPorTamanho = null;
    }
    existente.tipoProduto = novo.tipoProduto;
    if (novo.itensCombo != null && novo.itensCombo!.isNotEmpty) {
      existente.itensCombo = novo.itensCombo!.map((m) => Map<String, dynamic>.from(m)).toList();
    } else {
      existente.itensCombo = null;
    }

    if (novo.variacoes != null && novo.variacoes!.isNotEmpty) {
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
    } else {
      // Sem variações novas: zera variacoes e recalcula quantidade a partir do estoquePorTamanho (se existir).
      existente.variacoes = null;
      if (existente.estoquePorTamanho.isNotEmpty) {
        existente.quantidade =
            existente.estoquePorTamanho.values.fold(0, (a, b) => a + b);
      }
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
