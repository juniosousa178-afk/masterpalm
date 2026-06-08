// Guarda a grade canônica em estoque_produtos — completa, preserva ou reconstrói
// antes do write e na reidratação pós-save.

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'logger.dart';
import 'produto_form_grade_hydration.dart';
import 'produto_variacao_extra.dart';
import '../models/produto.dart';

/// Resultado da completação da grade para push em estoque_produtos.
class ProdutoEstoqueGradePushResult {
  const ProdutoEstoqueGradePushResult({
    required this.variacoes,
    required this.variacoesExtraTipo,
    required this.estoquePorTamanho,
    required this.tamanhos,
    this.precoPorTamanho,
    this.origem,
    this.acao,
  });

  final Map<String, dynamic> variacoes;
  final Map<String, dynamic> variacoesExtraTipo;
  final Map<String, int> estoquePorTamanho;
  final List<String> tamanhos;
  final Map<String, double>? precoPorTamanho;
  final String? origem;
  final String? acao;
}

/// Resultado da merge de grade remota na reidratação pós-save.
class ProdutoEstoqueGradeRehydrateResult {
  const ProdutoEstoqueGradeRehydrateResult({
    required this.aplicarGradeRemota,
    this.aviso,
    this.variacoes,
    this.variacoesExtraTipo,
    this.estoquePorTamanho,
    this.tamanhos,
    this.precoPorTamanho,
  });

  final bool aplicarGradeRemota;
  final String? aviso;
  final Map<String, dynamic>? variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final Map<String, int>? estoquePorTamanho;
  final List<String>? tamanhos;
  final Map<String, double>? precoPorTamanho;
}

class ProdutoEstoqueGradeCanonicalGuard {
  ProdutoEstoqueGradeCanonicalGuard._();

  static const avisoGradeRemotaIncompleta =
      'Produto salvo, mas a grade remota retornou incompleta. '
      'Mantivemos a grade local para evitar perda de variações.';

  @visibleForTesting
  static Map<String, dynamic> mapFromDynamic(dynamic raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  @visibleForTesting
  static Map<String, int> estoqueFromDynamic(dynamic raw) {
    if (raw is! Map || raw.isEmpty) return {};
    return raw.map(
      (k, v) => MapEntry(
        k.toString(),
        ProdutoVariacaoExtra.valorFirestoreComoInt(v),
      ),
    );
  }

  @visibleForTesting
  static List<String> tamanhosFromDynamic(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  @visibleForTesting
  static bool produtoIndicaGradeSignals({
    required Map<String, dynamic> variacoes,
    required Map<String, dynamic> variacoesExtraTipo,
    required Map<String, int> estoquePorTamanho,
    required List<String> tamanhos,
  }) {
    return variacoes.isNotEmpty ||
        variacoesExtraTipo.isNotEmpty ||
        estoquePorTamanho.isNotEmpty ||
        tamanhos.isNotEmpty;
  }

  @visibleForTesting
  static bool gradeCoreCompleta({
    required Map<String, dynamic> variacoes,
    required Map<String, int> estoquePorTamanho,
  }) {
    return variacoes.isNotEmpty && estoquePorTamanho.isNotEmpty;
  }

  @visibleForTesting
  static bool gradePushIncompleta({
    required Map<String, dynamic> variacoes,
    required Map<String, dynamic> variacoesExtraTipo,
    required Map<String, int> estoquePorTamanho,
    required List<String> tamanhos,
  }) {
    if (!produtoIndicaGradeSignals(
      variacoes: variacoes,
      variacoesExtraTipo: variacoesExtraTipo,
      estoquePorTamanho: estoquePorTamanho,
      tamanhos: tamanhos,
    )) {
      return false;
    }
    return variacoes.isEmpty || estoquePorTamanho.isEmpty;
  }

  @visibleForTesting
  static bool remoteEstoqueGradeCompleta(Map<String, dynamic>? data) {
    if (data == null) return false;
    return gradeCoreCompleta(
      variacoes: mapFromDynamic(data['variacoes']),
      estoquePorTamanho: estoqueFromDynamic(data['estoquePorTamanho']),
    );
  }

  @visibleForTesting
  static bool remoteEstoqueGradeIncompleta(Map<String, dynamic>? data) {
    if (data == null) return false;
    return gradePushIncompleta(
      variacoes: mapFromDynamic(data['variacoes']),
      variacoesExtraTipo: mapFromDynamic(data['variacoesExtraTipo']),
      estoquePorTamanho: estoqueFromDynamic(data['estoquePorTamanho']),
      tamanhos: tamanhosFromDynamic(data['tamanhos']),
    );
  }

  @visibleForTesting
  static bool localProdutoGradeCompleta(Produto local) {
    return gradeCoreCompleta(
      variacoes: mapFromDynamic(local.variacoes),
      estoquePorTamanho: Map<String, int>.from(local.estoquePorTamanho),
    );
  }

  @visibleForTesting
  static bool localProdutoIndicaGrade(Produto local) {
    return produtoIndicaGradeSignals(
      variacoes: mapFromDynamic(local.variacoes),
      variacoesExtraTipo: mapFromDynamic(local.variacoesExtraTipo),
      estoquePorTamanho: Map<String, int>.from(local.estoquePorTamanho),
      tamanhos: List<String>.from(local.tamanhos),
    );
  }

  static Map<String, dynamic> _filtrarVariacoesPorTamanhos(
    Map<String, dynamic> variacoes,
    List<String> tamanhos,
  ) {
    if (tamanhos.isEmpty) return Map<String, dynamic>.from(variacoes);
    final allow = tamanhos.toSet();
    final out = <String, dynamic>{};
    for (final e in variacoes.entries) {
      if (allow.contains(e.key.toString())) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static Map<String, int> _filtrarEstoquePorTamanhos(
    Map<String, int> estoque,
    List<String> tamanhos,
  ) {
    if (tamanhos.isEmpty) return Map<String, int>.from(estoque);
    final allow = tamanhos.toSet();
    final out = <String, int>{};
    for (final e in estoque.entries) {
      if (allow.contains(e.key)) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static Map<String, dynamic> _filtrarExtraPorTamanhos(
    Map<String, dynamic> extra,
    List<String> tamanhos,
  ) {
    if (tamanhos.isEmpty) return Map<String, dynamic>.from(extra);
    final allow = tamanhos.toSet();
    final out = <String, dynamic>{};
    for (final e in extra.entries) {
      if (allow.contains(e.key.toString())) {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  @visibleForTesting
  static Map<String, dynamic> reconstructVariacoesFromSignals({
    required Map<String, dynamic> variacoesExtraTipo,
    required List<String> tamanhos,
    required Map<String, int> estoquePorTamanhoHint,
    required int quantidade,
  }) {
    if (estoquePorTamanhoHint.isNotEmpty) {
      return produtoFormVariacoesFromEstoquePorTamanho(estoquePorTamanhoHint);
    }

    if (variacoesExtraTipo.isEmpty) return {};

    final sizes = <String>{
      ...tamanhos,
      ...variacoesExtraTipo.keys.map((k) => k.toString()),
    }..remove('sem-tamanho');

    var cellCount = 0;
    for (final tam in sizes) {
      final corMap = variacoesExtraTipo[tam];
      if (corMap is Map) cellCount += corMap.length;
    }

    final variacoes = <String, dynamic>{};
    for (final tam in sizes) {
      final corMap = variacoesExtraTipo[tam];
      if (corMap is! Map || corMap.isEmpty) continue;

      final inner = <String, dynamic>{};
      if (corMap.length == 1 && estoquePorTamanhoHint.containsKey(tam)) {
        inner[corMap.keys.first.toString()] = estoquePorTamanhoHint[tam]!;
      } else if (cellCount > 0 && quantidade > 0) {
        var perCell = quantidade ~/ cellCount;
        var remainder = quantidade % cellCount;
        for (final corEntry in corMap.entries) {
          var q = perCell;
          if (remainder > 0) {
            q++;
            remainder--;
          }
          if (q <= 0) q = 1;
          inner[corEntry.key.toString()] = q;
        }
      } else {
        for (final corEntry in corMap.entries) {
          inner[corEntry.key.toString()] = 1;
        }
      }

      if (inner.isNotEmpty) {
        variacoes[tam] = inner;
      }
    }
    return variacoes;
  }

  static Map<String, int> _estoqueFromVariacoes(Map<String, dynamic> variacoes) {
    if (variacoes.isEmpty) return {};
    return produtoFormEstoquePorTamanhoFromVariacoes(variacoes);
  }

  static void _logGradeCanonical(
    String tag, {
    required String lojaId,
    required String produtoId,
    required String origem,
    required Map<String, dynamic> variacoes,
    required Map<String, dynamic> variacoesExtraTipo,
    required Map<String, int> estoquePorTamanho,
    required List<String> tamanhos,
    required int quantidade,
  }) {
    logW(
      '[$tag] lojaId=$lojaId produtoId=$produtoId origem=$origem '
      'hasVariacoes=${variacoes.isNotEmpty} '
      'hasEstoquePorTamanho=${estoquePorTamanho.isNotEmpty} '
      'hasTamanhos=${tamanhos.isNotEmpty} '
      'hasVariacoesExtraTipo=${variacoesExtraTipo.isNotEmpty} '
      'quantidade=$quantidade',
      tag: tag,
    );
  }

  /// Completa o payload de grade antes do write em estoque_produtos.
  ///
  /// Prioridade: push/tela → local não filtrado → remoto estoque → reconstrução
  /// (live/draft só como fallback de reconstrução).
  static ProdutoEstoqueGradePushResult completeForEstoquePush({
    required String lojaId,
    required String produtoId,
    required Map<String, dynamic> variacoesPush,
    required Map<String, dynamic> variacoesExtraPush,
    required Map<String, int> estoquePorTamPush,
    required List<String> tamanhosPush,
    Map<String, double>? precoPorTamanhoPush,
    required int quantidade,
    Map<String, dynamic>? existingEstoqueData,
    Map<String, dynamic>? localUnfilteredVariacoes,
    Map<String, int>? localUnfilteredEstoque,
    Map<String, dynamic>? localUnfilteredExtra,
    List<String>? localUnfilteredTamanhos,
    Map<String, dynamic>? fallbackCatalogData,
    ProdutoFormGradeBaseline? baseline,
  }) {
    var variacoes = Map<String, dynamic>.from(variacoesPush);
    var extra = Map<String, dynamic>.from(variacoesExtraPush);
    var estoque = Map<String, int>.from(estoquePorTamPush);
    var tamanhos = List<String>.from(tamanhosPush);
    var preco = precoPorTamanhoPush;

    if (!gradePushIncompleta(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
    )) {
      if (variacoes.isNotEmpty && estoque.isEmpty) {
        estoque = _estoqueFromVariacoes(variacoes);
      } else if (estoque.isNotEmpty && variacoes.isEmpty) {
        variacoes = produtoFormVariacoesFromEstoquePorTamanho(estoque);
      }
      return ProdutoEstoqueGradePushResult(
        variacoes: variacoes,
        variacoesExtraTipo: extra,
        estoquePorTamanho: estoque,
        tamanhos: tamanhos,
        precoPorTamanho: preco,
      );
    }

    String? acao;
    String origem = 'push_incompleto';

    Map<String, dynamic> pickVariacoes(Map<String, dynamic> src, String from) {
      if (src.isEmpty) return {};
      acao ??= 'preserve';
      origem = from;
      return _filtrarVariacoesPorTamanhos(src, tamanhos);
    }

    Map<String, int> pickEstoque(Map<String, int> src, String from) {
      if (src.isEmpty) return {};
      acao ??= 'preserve';
      origem = from;
      return _filtrarEstoquePorTamanhos(src, tamanhos);
    }

    Map<String, dynamic> pickExtra(Map<String, dynamic> src, String from) {
      if (src.isEmpty) return extra;
      if (extra.isEmpty) {
        acao ??= 'preserve';
        origem = from;
        return _filtrarExtraPorTamanhos(src, tamanhos);
      }
      return extra;
    }

    // 1. Local não filtrado (estado da tela/Hive antes do tombstone).
    if (variacoes.isEmpty && localUnfilteredVariacoes != null) {
      variacoes = pickVariacoes(localUnfilteredVariacoes, 'local_unfiltered');
    }
    if (estoque.isEmpty && localUnfilteredEstoque != null) {
      estoque = pickEstoque(localUnfilteredEstoque, 'local_unfiltered');
    }
    if (extra.isEmpty && localUnfilteredExtra != null) {
      extra = pickExtra(localUnfilteredExtra, 'local_unfiltered');
    }
    if (tamanhos.isEmpty && localUnfilteredTamanhos != null) {
      tamanhos = List<String>.from(localUnfilteredTamanhos);
    }

    // 2. Baseline capturado ao abrir o formulário.
    if (baseline != null && produtoFormBaselineHadGrade(baseline)) {
      final basePayload = produtoFormBaselineGradePayload(baseline);
      if (variacoes.isEmpty && basePayload.variacoes.isNotEmpty) {
        variacoes = pickVariacoes(basePayload.variacoes, 'baseline');
      }
      if (estoque.isEmpty && basePayload.estoquePorTamanho.isNotEmpty) {
        estoque = pickEstoque(basePayload.estoquePorTamanho, 'baseline');
      }
      if (extra.isEmpty && basePayload.variacoesExtraTipo != null) {
        extra = pickExtra(basePayload.variacoesExtraTipo!, 'baseline');
      }
      if (tamanhos.isEmpty && basePayload.tamanhos.isNotEmpty) {
        tamanhos = List<String>.from(basePayload.tamanhos);
      }
    }

    // 3. Documento remoto anterior de estoque_produtos.
    if (existingEstoqueData != null) {
      if (variacoes.isEmpty) {
        variacoes = pickVariacoes(
          mapFromDynamic(existingEstoqueData['variacoes']),
          'estoque_remoto',
        );
      }
      if (estoque.isEmpty) {
        estoque = pickEstoque(
          estoqueFromDynamic(existingEstoqueData['estoquePorTamanho']),
          'estoque_remoto',
        );
      }
      if (extra.isEmpty) {
        extra = pickExtra(
          mapFromDynamic(existingEstoqueData['variacoesExtraTipo']),
          'estoque_remoto',
        );
      }
      if (tamanhos.isEmpty) {
        tamanhos = tamanhosFromDynamic(existingEstoqueData['tamanhos']);
      }
      if (preco == null || preco.isEmpty) {
        final rawPpt = existingEstoqueData['precoPorTamanho'];
        if (rawPpt is Map && rawPpt.isNotEmpty) {
          preco = rawPpt.map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          );
        }
      }
    }

    // 4. Fallback live/draft — somente para preencher lacunas.
    if (fallbackCatalogData != null) {
      if (variacoes.isEmpty) {
        variacoes = pickVariacoes(
          mapFromDynamic(fallbackCatalogData['variacoes']),
          'catalog_fallback',
        );
      }
      if (estoque.isEmpty) {
        estoque = pickEstoque(
          estoqueFromDynamic(fallbackCatalogData['estoquePorTamanho']),
          'catalog_fallback',
        );
      }
      if (extra.isEmpty) {
        extra = pickExtra(
          mapFromDynamic(fallbackCatalogData['variacoesExtraTipo']),
          'catalog_fallback',
        );
      }
    }

    // Reconstrução segura quando ainda incompleto.
    if (gradePushIncompleta(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
    )) {
      final hint = Map<String, int>.from(estoque);
      final rebuilt = reconstructVariacoesFromSignals(
        variacoesExtraTipo: extra,
        tamanhos: tamanhos,
        estoquePorTamanhoHint: hint,
        quantidade: quantidade,
      );
      if (rebuilt.isNotEmpty) {
        variacoes = rebuilt;
        estoque = _estoqueFromVariacoes(variacoes);
        acao = 'reconstruct';
        origem = 'extra_tipo_tamanhos';
      }
    }

    if (variacoes.isNotEmpty && estoque.isEmpty) {
      estoque = _estoqueFromVariacoes(variacoes);
    } else if (estoque.isNotEmpty && variacoes.isEmpty) {
      variacoes = produtoFormVariacoesFromEstoquePorTamanho(estoque);
    }

    if (acao == 'preserve') {
      _logGradeCanonical(
        'PRODUTO_GRADE_CANONICAL_PRESERVE',
        lojaId: lojaId,
        produtoId: produtoId,
        origem: origem,
        variacoes: variacoes,
        variacoesExtraTipo: extra,
        estoquePorTamanho: estoque,
        tamanhos: tamanhos,
        quantidade: quantidade,
      );
    } else if (acao == 'reconstruct') {
      _logGradeCanonical(
        'PRODUTO_GRADE_CANONICAL_RECONSTRUCT',
        lojaId: lojaId,
        produtoId: produtoId,
        origem: origem,
        variacoes: variacoes,
        variacoesExtraTipo: extra,
        estoquePorTamanho: estoque,
        tamanhos: tamanhos,
        quantidade: quantidade,
      );
    } else if (gradePushIncompleta(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
    )) {
      _logGradeCanonical(
        'PRODUTO_GRADE_CANONICAL_INCOMPLETE_BLOCKED',
        lojaId: lojaId,
        produtoId: produtoId,
        origem: origem,
        variacoes: variacoes,
        variacoesExtraTipo: extra,
        estoquePorTamanho: estoque,
        tamanhos: tamanhos,
        quantidade: quantidade,
      );
    }

    return ProdutoEstoqueGradePushResult(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
      precoPorTamanho: preco,
      origem: origem,
      acao: acao,
    );
  }

  /// Decide como aplicar grade na reidratação pós-save.
  static ProdutoEstoqueGradeRehydrateResult resolveForRehydrate({
    required Produto local,
    required Map<String, dynamic> remoteData,
    Map<String, dynamic>? fallbackCatalogData,
    ProdutoFormGradeBaseline? baseline,
  }) {
    final remoteCompleta = remoteEstoqueGradeCompleta(remoteData);
    final remoteIncompleta = remoteEstoqueGradeIncompleta(remoteData);
    final localCompleta = localProdutoGradeCompleta(local);
    final localIndica = localProdutoIndicaGrade(local);
    final baselineIndica =
        baseline != null && produtoFormBaselineHadGrade(baseline);

    if (remoteCompleta) {
      return const ProdutoEstoqueGradeRehydrateResult(aplicarGradeRemota: true);
    }

    if (!remoteIncompleta && !localIndica && !baselineIndica) {
      return const ProdutoEstoqueGradeRehydrateResult(aplicarGradeRemota: true);
    }

    Map<String, dynamic> variacoes = {};
    Map<String, dynamic> extra = {};
    Map<String, int> estoque = {};
    List<String> tamanhos = [];
    Map<String, double>? preco;

    if (localCompleta) {
      variacoes = mapFromDynamic(local.variacoes);
      estoque = Map<String, int>.from(local.estoquePorTamanho);
      extra = mapFromDynamic(local.variacoesExtraTipo);
      tamanhos = List<String>.from(local.tamanhos);
      preco = local.precoPorTamanho == null
          ? null
          : Map<String, double>.from(local.precoPorTamanho!);
    } else if (baseline != null && produtoFormBaselineHadGrade(baseline)) {
      final base = produtoFormBaselineGradePayload(baseline);
      variacoes = Map<String, dynamic>.from(base.variacoes);
      estoque = Map<String, int>.from(base.estoquePorTamanho);
      extra = base.variacoesExtraTipo == null
          ? {}
          : Map<String, dynamic>.from(base.variacoesExtraTipo!);
      tamanhos = List<String>.from(base.tamanhos);
    }

    if (gradePushIncompleta(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
    )) {
      final completed = completeForEstoquePush(
        lojaId: local.lojaId,
        produtoId: local.idFirebase.isNotEmpty
            ? local.idFirebase
            : local.slug,
        variacoesPush: mapFromDynamic(remoteData['variacoes']),
        variacoesExtraPush: mapFromDynamic(remoteData['variacoesExtraTipo']),
        estoquePorTamPush: estoqueFromDynamic(remoteData['estoquePorTamanho']),
        tamanhosPush: tamanhosFromDynamic(remoteData['tamanhos']),
        quantidade:
            (remoteData['quantidade'] as num?)?.toInt() ?? local.quantidade,
        existingEstoqueData: remoteData,
        localUnfilteredVariacoes: mapFromDynamic(local.variacoes),
        localUnfilteredEstoque: Map<String, int>.from(local.estoquePorTamanho),
        localUnfilteredExtra: mapFromDynamic(local.variacoesExtraTipo),
        localUnfilteredTamanhos: List<String>.from(local.tamanhos),
        fallbackCatalogData: fallbackCatalogData,
        baseline: baseline,
      );
      variacoes = completed.variacoes;
      estoque = completed.estoquePorTamanho;
      extra = completed.variacoesExtraTipo;
      tamanhos = completed.tamanhos;
      preco = completed.precoPorTamanho ?? preco;
    }

    if (gradeCoreCompleta(variacoes: variacoes, estoquePorTamanho: estoque)) {
      return ProdutoEstoqueGradeRehydrateResult(
        aplicarGradeRemota: false,
        aviso: avisoGradeRemotaIncompleta,
        variacoes: variacoes,
        variacoesExtraTipo: extra.isEmpty ? null : extra,
        estoquePorTamanho: estoque,
        tamanhos: tamanhos,
        precoPorTamanho: preco,
      );
    }

    if (localIndica || baselineIndica) {
      _logGradeCanonical(
        'PRODUTO_GRADE_CANONICAL_INCOMPLETE_BLOCKED',
        lojaId: local.lojaId,
        produtoId: local.idFirebase.isNotEmpty
            ? local.idFirebase
            : local.slug,
        origem: 'rehydrate_pos_save',
        variacoes: variacoes,
        variacoesExtraTipo: extra,
        estoquePorTamanho: estoque,
        tamanhos: tamanhos,
        quantidade: local.quantidade,
      );
      return ProdutoEstoqueGradeRehydrateResult(
        aplicarGradeRemota: false,
        aviso: avisoGradeRemotaIncompleta,
      );
    }

    return const ProdutoEstoqueGradeRehydrateResult(aplicarGradeRemota: true);
  }
}
