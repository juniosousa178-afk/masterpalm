// lib/services/produto_upsert_service.dart
// Serviço de upsert para evitar duplicação de produtos no estoque.
// Chave única: (a) código de barras, (b) SKU, (c) nome normalizado + categoria.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/combo_config_canonical.dart';
import '../core/logger.dart';
import '../core/produto_custo_guard.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import 'combo_receita_normalizacao.dart';
import '../core/produto_firestore_doc_id_validator.dart';
import 'produto_import_doc_id_helper.dart';

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

    // a) Código de barras no campo dedicado (+ legado slug)
    if (codigoBarras != null && codigoBarras.trim().isNotEmpty) {
      final b = codigoBarras.trim();
      if (p.codigoBarras == b) return p;
      if (p.slug == b || p.slug == '$lojaId-$b') return p;
    }

    // b) SKU no campo dedicado (+ legado slug)
    if (sku != null && sku.trim().isNotEmpty) {
      final s = sku.trim();
      if (p.sku == s) return p;
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
    final pBarras = p.codigoBarras.trim();
    final pSku = p.sku.trim();
    if (codigoBarras != null && codigoBarras.trim().isNotEmpty) {
      final b = codigoBarras.trim();
      final ok = pBarras.isEmpty ||
          pBarras == b ||
          pSlug == b ||
          pSlug == '$lojaId-$b';
      if (!ok) return true;
    }
    if (sku != null && sku.trim().isNotEmpty) {
      final s = sku.trim();
      final ok = pSku.isEmpty || pSku == s || pSlug == s || pSlug == '$lojaId-$s';
      if (!ok) return true;
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

/// Import sem mapa de variações, sem grade por tamanho e sem preço por tamanho (não é combo).
bool _importNovoIndicaProdutoSimples(Produto novo) {
  if (novo.tipoProduto == 'combo') return false;
  if (_mapaComDados(novo.variacoes)) return false;
  if (_mapaComDados(novo.estoquePorTamanho)) return false;
  if (novo.precoPorTamanho != null && novo.precoPorTamanho!.isNotEmpty) {
    return false;
  }
  return true;
}

void _mergeProdutoExistente(
  Produto existente,
  Produto novo, {
  ImportCustoInput importCusto = ImportCustoInput.colunaAusente,
}) {
  // Campos numéricos principais (importação traz valores concretos)
  existente.quantidade = novo.quantidade;
  ProdutoCustoGuard.applyImportCustoMerge(
    existente: existente,
    importCusto: importCusto,
    fallbackNovoProduto: novo.custoReal,
  );
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
  if (_temTexto(novo.sku)) existente.sku = novo.sku.trim();
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

  if (_importNovoIndicaProdutoSimples(novo)) {
    final tinhaVariacaoOuExtra = (existente.variacoes != null &&
            existente.variacoes!.isNotEmpty) ||
        (existente.variacoesExtraTipo != null &&
            existente.variacoesExtraTipo!.isNotEmpty);
    final tinhaGrade = existente.estoquePorTamanho.isNotEmpty;
    if (tinhaVariacaoOuExtra || tinhaGrade) {
      logW(
        '[VARIACAO_CLEAR] import merge: payload simples → removendo variações/extras/grade antigas',
        tag: 'VARIACAO_CLEAR',
      );
    }
    existente.variacoes = null;
    existente.variacoesExtraTipo = null;
    existente.estoquePorTamanho = <String, int>{};
  }
}

/// Resultado do upsert de importação (docId seguro).
enum UpsertImportResult {
  inserted,
  updated,
  skippedConflict,
  recuperacaoManualNecessaria,
  falhouIdInvalido,
}

typedef UpsertImportResultWithProduct = (UpsertImportResult, Produto?);

Future<void> _aplicarCodigosExternosNoProduto(
  Produto produto, {
  String? codigoBarras,
  String? sku,
}) async {
  if (codigoBarras != null && codigoBarras.trim().isNotEmpty) {
    produto.codigoBarras = codigoBarras.trim();
  }
  if (sku != null && sku.trim().isNotEmpty) {
    produto.sku = sku.trim();
  }
}

/// Upsert exclusivo da importação Excel: docId seguro, SKU/código só em campos.
Future<UpsertImportResultWithProduct> upsertProdutoParaImportacao(
  Box<Produto> box,
  String lojaId,
  Produto novo,
  Box<Venda> vendasBox, {
  String? codigoBarras,
  String? sku,
  ImportCustoInput importCusto = ImportCustoInput.colunaAusente,
  void Function(String msg)? onLog,
}) async {
  final codigoBarrasStr = codigoBarras?.trim();
  final skuStr = sku?.trim();

  await _aplicarCodigosExternosNoProduto(
    novo,
    codigoBarras: codigoBarrasStr,
    sku: skuStr,
  );

  if (hasConflito(box, lojaId, novo.nome, novo.categoria,
      codigoBarras: codigoBarrasStr, sku: skuStr)) {
    onLog?.call('Conflito de códigos — linha ignorada.');
    return (UpsertImportResult.skippedConflict, null);
  }

  final existente = findProdutoExistente(
    box,
    lojaId,
    codigoBarras: codigoBarrasStr,
    sku: skuStr,
    nome: novo.nome,
    categoria: novo.categoria,
  );

  if (existente != null) {
    if (existente.key == null) {
      return (UpsertImportResult.skippedConflict, null);
    }

    _mergeProdutoExistente(existente, novo, importCusto: importCusto);
    await _aplicarCodigosExternosNoProduto(
      existente,
      codigoBarras: codigoBarrasStr,
      sku: skuStr,
    );

    if (novo.precoPorTamanho != null && novo.precoPorTamanho!.isNotEmpty) {
      existente.precoPorTamanho = Map<String, double>.from(novo.precoPorTamanho!);
    }
    if (novo.variacoes != null) {
      if (novo.variacoes!.isEmpty) {
        existente.variacoes = null;
        existente.variacoesExtraTipo = null;
        existente.estoquePorTamanho = _mapaComDados(novo.estoquePorTamanho)
            ? Map<String, int>.from(novo.estoquePorTamanho)
            : <String, int>{};
        existente.quantidade = novo.quantidade;
      } else {
        final Map<String, dynamic> deepCopy = {};
        for (final entry in novo.variacoes!.entries) {
          final value = entry.value;
          if (value is Map) {
            deepCopy[entry.key] = Map<String, dynamic>.from(
              value.map((k, v) => MapEntry(k.toString(), v)),
            );
          } else {
            deepCopy[entry.key] = value;
          }
        }
        existente.variacoes = deepCopy;
        existente.recalcularQuantidadeTotal();
      }
    } else if (novo.estoquePorTamanho.isNotEmpty) {
      existente.quantidade =
          existente.estoquePorTamanho.values.fold(0, (a, b) => a + b);
    }

    existente.custoEditadoNoCadastro = true;
    existente.updatedAt = DateTime.now();
    await existente.save();
    return (UpsertImportResult.updated, existente);
  }

  ProdutoImportDocIdHelper.aplicarDocIdLocalOfflineNoProduto(
    produto: novo,
    lojaId: lojaId,
  );

  final idCheck = ProdutoFirestoreDocIdValidator.validateProduto(
    storeId: lojaId,
    produto: novo,
  );
  if (!idCheck.ok) {
    return (UpsertImportResult.falhouIdInvalido, null);
  }

  novo.custoEditadoNoCadastro = true;
  novo.updatedAt = DateTime.now();
  await box.add(novo);
  await novo.save();
  return (UpsertImportResult.inserted, novo);
}

/// Upsert: atualiza se existir, insere se não existir.
/// Retorna (resultado, produto) para permitir sync no Firestore.
Future<UpsertResultWithProduct> upsertProduto(
  Box<Produto> box,
  String lojaId,
  Produto novo, {
  String? codigoBarras,
  String? sku,
  ImportCustoInput importCusto = ImportCustoInput.colunaAusente,
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

    _mergeProdutoExistente(existente, novo, importCusto: importCusto);

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

    if (codigoBarrasStr != null && codigoBarrasStr.isNotEmpty) {
      existente.codigoBarras = codigoBarrasStr;
    }
    if (skuStr != null && skuStr.isNotEmpty) {
      existente.sku = skuStr;
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

  if (codigoBarrasStr != null && codigoBarrasStr.isNotEmpty) {
    novo.codigoBarras = codigoBarrasStr;
  }
  if (skuStr != null && skuStr.isNotEmpty) {
    novo.sku = skuStr;
  }
  if (novo.slug.isEmpty) {
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
