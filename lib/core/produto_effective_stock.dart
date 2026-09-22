// Estoque efetivo para venda/auditoria: remoto > Hive quando sem pending.
// Não escreve no Firestore.

import '../models/produto.dart';
import 'produto_estoque_grade_snapshot.dart';
import 'produto_stock_revision.dart';
import 'produto_untracked_stock_conflict.dart';
import 'produto_variacao_extra.dart';

enum EffectiveStockKind {
  simple,
  variation,
  grade,
  combo,
}

extension EffectiveStockKindWire on EffectiveStockKind {
  String get wire => switch (this) {
        EffectiveStockKind.simple => 'simple',
        EffectiveStockKind.variation => 'variation',
        EffectiveStockKind.grade => 'grade',
        EffectiveStockKind.combo => 'combo',
      };
}

/// Células `tamanho|cor` → qty após normalizar aliases `sem-cor`.
Map<String, int> normalizeSemCorAliasCells(Map<String, int> rawCells) {
  if (rawCells.isEmpty) return {};
  final bySize = <String, Map<String, int>>{};
  for (final e in rawCells.entries) {
    final parts = e.key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : 'sem-tamanho';
    final cor = parts.length > 1 ? parts[1] : 'sem-cor';
    bySize.putIfAbsent(tam, () => <String, int>{})[cor] = e.value;
  }

  final out = <String, int>{};
  for (final sizeEntry in bySize.entries) {
    final tam = sizeEntry.key;
    final colors = sizeEntry.value;
    final hasSpecific = colors.keys.any(
      (c) => c.trim().isNotEmpty && c != 'sem-cor',
    );
    if (hasSpecific) {
      for (final c in colors.entries) {
        if (c.key == 'sem-cor') continue;
        if (c.value <= 0) continue;
        out[ProdutoEstoqueGradeSnapshot.variacaoId(tam, c.key)] = c.value;
      }
    } else {
      final q = colors['sem-cor'] ?? 0;
      if (q > 0) {
        out[ProdutoEstoqueGradeSnapshot.variacaoId(tam, 'sem-cor')] = q;
      }
    }
  }
  return out;
}

int sumNormalizedCells(Map<String, int> cells) =>
    cells.values.fold<int>(0, (a, b) => a + b);

Map<String, int> cellsFromVariacoesMap(Map<String, dynamic>? variacoes) {
  if (variacoes == null || variacoes.isEmpty) return {};
  final out = <String, int>{};
  variacoes.forEach((tam, cores) {
    if (cores is! Map) return;
    cores.forEach((cor, qtd) {
      out[ProdutoEstoqueGradeSnapshot.variacaoId(
        tam.toString(),
        cor.toString(),
      )] = ProdutoVariacaoExtra.valorFirestoreComoInt(qtd);
    });
  });
  return out;
}

/// Extrai células canônicas de um doc remoto (variacoes + estoquePorTamanho).
Map<String, int> canonicalCellsFromRemote(Map<String, dynamic> remote) {
  return ProdutoEstoqueGradeSnapshot.fromRemote(remote).cells;
}

Map<String, int> effectiveCanonicalCellsFromRemote(
  Map<String, dynamic> remote,
) {
  return normalizeSemCorAliasCells(canonicalCellsFromRemote(remote));
}

bool _hasRealVariationIdentity(Map<String, int> cells) {
  for (final key in cells.keys) {
    final parts = key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : '';
    final cor = parts.length > 1 ? parts[1] : '';
    final realTam = tam.isNotEmpty && tam != 'sem-tamanho';
    final realCor = cor.isNotEmpty && cor != 'sem-cor';
    if (realTam || realCor) return true;
  }
  return false;
}

/// Kind efetivo a partir do documento remoto autoritativo.
EffectiveStockKind effectiveStockKindFromRemote(Map<String, dynamic> remote) {
  final raw = (remote['stockKind'] ?? '').toString().trim().toLowerCase();
  if (raw == 'combo') return EffectiveStockKind.combo;
  if (raw == 'grade') return EffectiveStockKind.grade;
  if (raw == 'variation') return EffectiveStockKind.variation;

  final cells = effectiveCanonicalCellsFromRemote(remote);
  final positive = cells.entries.where((e) => e.value > 0).map((e) => e.key);
  final positiveMap = {
    for (final k in positive) k: cells[k]!,
  };
  if (_hasRealVariationIdentity(positiveMap.isNotEmpty ? positiveMap : cells)) {
    return EffectiveStockKind.variation;
  }
  return EffectiveStockKind.simple;
}

EffectiveStockKind effectiveStockKindFromProduto(Produto p) {
  if (p.ehCombo) return EffectiveStockKind.combo;
  final snap = ProdutoEstoqueGradeSnapshot.fromProduto(p);
  final norm = normalizeSemCorAliasCells(snap.cells);
  if (_hasRealVariationIdentity(norm)) return EffectiveStockKind.variation;
  return EffectiveStockKind.simple;
}

/// Opções de venda a partir de células normalizadas (qty > 0).
List<({String tamanho, String cor, int qty, String variationKey})>
    saleOptionsFromNormalizedCells(Map<String, int> normalized) {
  final out = <({String tamanho, String cor, int qty, String variationKey})>[];
  final keys = normalized.keys.toList()..sort();
  for (final key in keys) {
    final qty = normalized[key] ?? 0;
    if (qty <= 0) continue;
    final parts = key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : '';
    final cor = parts.length > 1 ? parts[1] : 'sem-cor';
    final tamanho = tam == 'sem-tamanho' ? '' : tam;
    final corOut = cor == 'sem-cor' ? '' : cor;
    out.add((
      tamanho: tamanho,
      cor: corOut,
      qty: qty,
      variationKey: key,
    ));
  }
  return out;
}

/// Aplica metadados de estoque remotos no [Produto] (cache local).
/// Não chama se houver pending stock local.
/// Retorna true se aplicou.
bool applyAuthoritativeRemoteStockToProduto(
  Produto local, {
  required Map<String, dynamic> remote,
  bool updateQuantity = true,
}) {
  if (hasPendingStockMutation(local)) return false;

  // Forensic: same-rev/same-op qty divergence must be recorded before overwrite.
  if (updateQuantity) {
    captureUntrackedConflictBeforeAuthoritativeOverwrite(
      local: local,
      remote: remote,
      source: 'applyAuthoritativeRemoteStockToProduto',
    );
  }

  final kind = effectiveStockKindFromRemote(remote);
  final cells = effectiveCanonicalCellsFromRemote(remote);
  final remoteQty = (remote['quantidade'] as num?)?.toInt();
  final remoteRev = parseStockRevisionFromRemote(remote);
  final remoteOp = parseStockOperationIdFromRemote(remote);

  if (updateQuantity && remoteQty != null) {
    local.quantidade = remoteQty < 0 ? 0 : remoteQty;
  }

  // Contrato: mutação de estoque local = REMOTE_HYDRATION (qty alinhada) OU
  // PENDING_STOCK_INTENT. Nunca adotar revision/op remota preservando qty
  // divergente (causa dos 51 LOCAL_UNTRACKED com same rev/op).
  final remoteQtyNorm =
      remoteQty == null ? null : (remoteQty < 0 ? 0 : remoteQty);
  final qtyMatchesRemote =
      remoteQtyNorm == null || local.quantidade == remoteQtyNorm;
  final mayAdoptRevision = updateQuantity || qtyMatchesRemote;
  assert(() {
    if (!updateQuantity &&
        remoteQtyNorm != null &&
        local.quantidade != remoteQtyNorm) {
      // LOCAL_QTY_MUTATION_WITHOUT_TRACKING fingerprint — não adotar rev/op.
      return !mayAdoptRevision;
    }
    return true;
  }(), 'LOCAL_QTY_MUTATION_WITHOUT_TRACKING: cannot adopt remote rev/op');
  if (mayAdoptRevision) {
    local.stockRevision = remoteRev;
    if (remoteOp != null && remoteOp.isNotEmpty) {
      local.confirmedStockOperationId = remoteOp;
    }
  }

  if (kind == EffectiveStockKind.simple) {
    // Remoto simple: limpa grade stale se remoto não tem células reais.
    if (!_hasRealVariationIdentity(cells)) {
      local.variacoes = null;
      local.estoquePorTamanho = {};
    }
  } else if (kind == EffectiveStockKind.variation ||
      kind == EffectiveStockKind.grade) {
    _applyNormalizedCellsToProdutoGrade(local, cells);
  }

  final serverAt = parseFirestoreStockUpdatedAtField(remote);
  if (serverAt != null) {
    applyServerStockVersionToProduto(local, serverAt);
  }
  return true;
}

/// Só estrutura de variação para UI de venda (mesmo com pending).
/// Não altera qty, revision, operationId nem limpa pending.
bool applyRemoteVariationStructureForSaleUi(
  Produto local, {
  required Map<String, dynamic> remote,
}) {
  final kind = effectiveStockKindFromRemote(remote);
  final cells = effectiveCanonicalCellsFromRemote(remote);
  if (kind != EffectiveStockKind.variation &&
      kind != EffectiveStockKind.grade &&
      !_hasRealVariationIdentity(cells)) {
    return false;
  }
  if (cells.isEmpty) return false;
  _applyNormalizedCellsToProdutoGrade(local, cells);
  return true;
}

void _applyNormalizedCellsToProdutoGrade(
  Produto local,
  Map<String, int> cells,
) {
  final vars = <String, dynamic>{};
  final ept = <String, int>{};
  for (final e in cells.entries) {
    if (e.value < 0) continue;
    final parts = e.key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : 'sem-tamanho';
    final cor = parts.length > 1 ? parts[1] : 'sem-cor';
    vars.putIfAbsent(tam, () => <String, dynamic>{});
    final inner = vars[tam] as Map<String, dynamic>;
    inner[cor] = e.value;
    ept[tam] = (ept[tam] ?? 0) + e.value;
  }
  if (vars.isNotEmpty) {
    local.variacoes = vars;
    local.estoquePorTamanho = ept;
  }
}

/// Snapshot imutável dos campos de estoque (diagnóstico / comparação).
Map<String, dynamic> captureLocalStockSnapshot(Produto p) {
  final kindWire = p.ehCombo
      ? 'combo'
      : (p.usaVariacoes || p.estoquePorTamanho.isNotEmpty)
          ? 'variation'
          : 'simple';
  return {
    'LOCAL_PRODUCT_ID': p.idFirebase,
    'LOCAL_PRODUCT_CODE': p.codigoBarras,
    'LOCAL_PRODUCT_NAME': p.nome,
    'LOCAL_PRODUCT_TYPE': p.ehCombo ? 'combo' : 'simples',
    'LOCAL_STOCK_KIND': kindWire,
    'LOCAL_QTY': p.quantidade,
    'LOCAL_STOCK_REVISION': p.stockRevision,
    'LOCAL_STOCK_OPERATION_ID': p.confirmedStockOperationId,
    'LOCAL_USA_VARIACOES': p.usaVariacoes,
    'LOCAL_VARIATIONS': p.variacoes == null
        ? null
        : _deepCopyDynamicMap(p.variacoes!),
    'LOCAL_ESTOQUE_POR_TAMANHO': Map<String, int>.from(p.estoquePorTamanho),
    'LOCAL_TAMANHOS': List<String>.from(p.tamanhos),
    'LOCAL_GRADE_CELLS':
        Map<String, int>.from(ProdutoEstoqueGradeSnapshot.fromProduto(p).cells),
    'LOCAL_PENDING_OPERATION_ID': p.pendingStockOperationId,
    'LOCAL_PENDING_BASE_REVISION': p.pendingStockBaseRevision,
    'LOCAL_UPDATED_AT': p.updatedAt?.toIso8601String(),
    'LOCAL_EFFECTIVE_KIND': effectiveStockKindFromProduto(p).wire,
  };
}

Map<String, dynamic> _deepCopyDynamicMap(Map<String, dynamic> src) {
  final out = <String, dynamic>{};
  for (final e in src.entries) {
    final v = e.value;
    if (v is Map) {
      out[e.key] = _deepCopyDynamicMap(Map<String, dynamic>.from(v));
    } else if (v is List) {
      out[e.key] = List<dynamic>.from(v);
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

/// Reconstrói mapa `variacoes` a partir de células normalizadas.
Map<String, dynamic> variacoesMapFromNormalizedCells(Map<String, int> cells) {
  final vars = <String, dynamic>{};
  for (final e in cells.entries) {
    final parts = e.key.split('|');
    final tam = parts.isNotEmpty ? parts[0] : 'sem-tamanho';
    final cor = parts.length > 1 ? parts[1] : 'sem-cor';
    vars.putIfAbsent(tam, () => <String, dynamic>{});
    (vars[tam] as Map<String, dynamic>)[cor] = e.value;
  }
  return vars;
}

int cellQtyForTamanhoCor(Produto p, String tamanho, String cor) {
  final t = tamanho.trim().isEmpty ? 'sem-tamanho' : tamanho.trim();
  final c = cor.trim().isEmpty ? 'sem-cor' : cor.trim();
  if (p.usaVariacoes && p.variacoes != null) {
    final m = p.variacoes![t];
    if (m is Map) {
      return ProdutoVariacaoExtra.valorFirestoreComoInt(m[c]);
    }
  }
  if (p.estoquePorTamanho.isNotEmpty && c == 'sem-cor') {
    return p.estoquePorTamanho[t] ?? 0;
  }
  return 0;
}
