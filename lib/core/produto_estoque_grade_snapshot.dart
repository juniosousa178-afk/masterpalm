// Snapshot normalizado da grade de estoque (variacaoId = tamanho|cor).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_version_fields.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';

/// Célula de estoque identificada por [variacaoId] canônico (`tamanho|cor`).
class ProdutoEstoqueGradeSnapshot {
  ProdutoEstoqueGradeSnapshot({
    required this.cells,
    required this.quantidadeTotal,
    required this.estoquePorTamanho,
    required this.estoquePorCor,
    required this.variacoes,
  });

  /// Chave `tamanho|cor` → quantidade.
  final Map<String, int> cells;

  final int quantidadeTotal;
  final Map<String, int> estoquePorTamanho;
  final Map<String, int> estoquePorCor;
  final Map<String, dynamic> variacoes;

  static String variacaoId(String tamanho, [String cor = 'sem-cor']) {
    final t = tamanho.trim().isEmpty ? 'sem-tamanho' : tamanho.trim();
    final c = cor.trim().isEmpty ? 'sem-cor' : cor.trim();
    return '$t|$c';
  }

  static Map<String, int> _cellsFromVariacoes(Map<String, dynamic>? vars) {
    final out = <String, int>{};
    if (vars == null || vars.isEmpty) return out;
    vars.forEach((tam, cores) {
      if (cores is! Map) return;
      cores.forEach((cor, qtd) {
        final q = ProdutoVariacaoExtra.valorFirestoreComoInt(qtd);
        // G11: chave duplicada → última ocorrência vence (determinístico).
        out[variacaoId(tam.toString(), cor.toString())] = q;
      });
    });
    return out;
  }

  static Map<String, int> _mapIntFromDynamic(Map? raw) {
    if (raw == null || raw.isEmpty) return {};
    return raw.map(
      (k, v) => MapEntry(
        k.toString(),
        ProdutoVariacaoExtra.valorFirestoreComoInt(v),
      ),
    );
  }

  static void _mergeCellsFromEstoquePorTamanho(
    Map<String, int> cells,
    Map<String, int> estTam,
  ) {
    for (final e in estTam.entries) {
      final id = variacaoId(e.key);
      if (!cells.containsKey(id)) {
        cells[id] = e.value;
      }
    }
  }

  static void _mergeCellsFromEstoquePorCor(
    Map<String, int> cells,
    Map<String, int> estCor,
  ) {
    for (final e in estCor.entries) {
      final id = variacaoId('', e.key);
      if (!cells.containsKey(id)) {
        cells[id] = e.value;
      }
    }
  }

  factory ProdutoEstoqueGradeSnapshot.fromProduto(Produto p) {
    final vars = p.variacoes == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(p.variacoes!);
    final cells = _cellsFromVariacoes(vars);
    final estTam = Map<String, int>.from(p.estoquePorTamanho);
    _mergeCellsFromEstoquePorTamanho(cells, estTam);
    if (cells.isEmpty && p.quantidade > 0) {
      cells[variacaoId('', 'sem-cor')] = p.quantidade;
    }
    return ProdutoEstoqueGradeSnapshot(
      cells: cells,
      quantidadeTotal: p.quantidade,
      estoquePorTamanho: estTam,
      estoquePorCor: const {},
      variacoes: vars,
    );
  }

  factory ProdutoEstoqueGradeSnapshot.fromRemote(Map<String, dynamic> data) {
    final varsRaw = data['variacoes'];
    final vars = varsRaw is Map
        ? Map<String, dynamic>.from(varsRaw)
        : <String, dynamic>{};
    final cells = _cellsFromVariacoes(vars.isEmpty ? null : vars);
    final estTam = _mapIntFromDynamic(
      data['estoquePorTamanho'] is Map ? data['estoquePorTamanho'] as Map : null,
    );
    final estCor = _mapIntFromDynamic(
      data['estoquePorCor'] is Map ? data['estoquePorCor'] as Map : null,
    );
    _mergeCellsFromEstoquePorTamanho(cells, estTam);
    _mergeCellsFromEstoquePorCor(cells, estCor);
    final total = (data['quantidade'] as num?)?.toInt() ?? 0;
    if (cells.isEmpty && total > 0) {
      cells[variacaoId('', 'sem-cor')] = total;
    }
    return ProdutoEstoqueGradeSnapshot(
      cells: cells,
      quantidadeTotal: total,
      estoquePorTamanho: estTam,
      estoquePorCor: estCor,
      variacoes: vars,
    );
  }

  /// Hash estável da grade (G7 — ordem de mapas irrelevante).
  String gradeHash() {
    final keys = cells.keys.toList()..sort();
    return keys.map((k) => '$k:${cells[k] ?? 0}').join('|');
  }

  bool gradeEquals(ProdutoEstoqueGradeSnapshot other) {
    return gradeHash() == other.gradeHash() &&
        quantidadeTotal == other.quantidadeTotal;
  }

  /// Células onde [other] tem quantidade estritamente maior.
  Map<String, int> cellsStrictlyGreaterThan(ProdutoEstoqueGradeSnapshot other) {
    final out = <String, int>{};
    final keys = {...cells.keys, ...other.cells.keys};
    for (final k in keys) {
      final remote = cells[k] ?? 0;
      final local = other.cells[k] ?? 0;
      if (remote > local) out[k] = remote;
    }
    return out;
  }

  /// Células onde [other] tem quantidade estritamente maior (perda local).
  Map<String, int> cellsStrictlyLessThan(ProdutoEstoqueGradeSnapshot other) {
    return other.cellsStrictlyGreaterThan(this);
  }

  bool gradeDiffersFrom(ProdutoEstoqueGradeSnapshot other) {
    return !gradeEquals(other);
  }
}

/// Decisão do pull para campos de estoque.
enum PullStockMergeDecision {
  /// Aplicar grade remota (versão de estoque autoritativa).
  acceptRemote,

  /// Manter grade local (snapshot remoto stale / regressão).
  preserveLocalGrade,
}

DateTime? parseFirestoreStockUpdatedAtField(Map<String, dynamic> data) {
  final u = data[kProdutoStockUpdatedAtField];
  if (u is Timestamp) return u.toDate();
  return null;
}

/// Avalia pull de estoque por revisão monotônica (R8.3).
///
/// Parâmetros de timestamp mantidos na assinatura por compatibilidade de testes;
/// **não** participam da decisão.
PullStockMergeDecision evaluatePullStockMerge({
  required Produto local,
  required Map<String, dynamic> remoteData,
  required DateTime? remoteStockUpdatedAt,
  required DateTime? localStockUpdatedAt,
  DateTime? localStockUpdatedAtServer,
}) {
  return evaluatePullStockMergeByRevision(
    local: local,
    remoteData: remoteData,
  );
}

/// Push/autosync por revisão — ignora relógio misto.
bool evaluatePushStockSkip({
  required Produto local,
  required Map<String, dynamic>? existingData,
  bool forcePushFromCadastro = false,
}) {
  return evaluatePushStockSkipByRevision(
    local: local,
    existingData: existingData,
    forcePushFromCadastro: forcePushFromCadastro,
  );
}

/// Espelha versão de estoque confirmada pelo servidor no Hive.
void applyServerStockVersionToProduto(Produto p, DateTime? serverStockAt) {
  if (serverStockAt == null) return;
  p.stockUpdatedAt = serverStockAt;
  p.stockUpdatedAtServer = serverStockAt;
}
