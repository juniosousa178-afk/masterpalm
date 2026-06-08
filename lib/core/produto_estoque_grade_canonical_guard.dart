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

  static dynamic _cloneVariacaoCelula(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return value;
  }

  /// [push] vence em células sobrepostas; chaves só em [base] permanecem.
  @visibleForTesting
  static Map<String, dynamic> mesclarVariacoesComPrioridadePush({
    required Map<String, dynamic> base,
    required Map<String, dynamic> push,
  }) {
    final out = <String, dynamic>{};
    for (final tam in {...base.keys, ...push.keys}) {
      final bk = base[tam];
      final pk = push[tam];
      if (pk == null) {
        if (bk != null) out[tam] = _cloneVariacaoCelula(bk);
        continue;
      }
      if (bk == null || bk is! Map) {
        out[tam] = _cloneVariacaoCelula(pk);
        continue;
      }
      if (pk is! Map) {
        out[tam] = pk;
        continue;
      }
      final inner = Map<String, dynamic>.from(bk);
      inner.addAll(Map<String, dynamic>.from(pk));
      out[tam] = inner;
    }
    return out;
  }

  @visibleForTesting
  static Map<String, int> mesclarEstoqueComPrioridadePush({
    required Map<String, int> base,
    required Map<String, int> push,
  }) {
    final out = Map<String, int>.from(base);
    out.addAll(push);
    return out;
  }

  @visibleForTesting
  static bool variacoesMesmasChaves(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if (a.length != b.length) return false;
    for (final te in a.entries) {
      if (!b.containsKey(te.key)) return false;
      final am = te.value;
      final bm = b[te.key];
      if (am is Map && bm is Map) {
        if (am.length != bm.length) return false;
        for (final ck in am.keys) {
          if (!bm.containsKey(ck)) return false;
        }
      } else if (am is Map || bm is Map) {
        return false;
      }
    }
    return true;
  }

  @visibleForTesting
  static bool variacoesLocalIsSubsetOfRemote(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    if (local.isEmpty || remote.isEmpty) return false;
    final localKeys = local.keys.map((k) => k.toString()).toSet();
    final remoteKeys = remote.keys.map((k) => k.toString()).toSet();
    if (!localKeys.every(remoteKeys.contains)) return false;
    return localKeys.length < remoteKeys.length;
  }

  static Map<String, dynamic> _coletarVariacoesPreservacao({
    ProdutoFormGradeBaseline? baseline,
    Map<String, dynamic>? existingEstoqueData,
    Map<String, dynamic>? localUnfilteredVariacoes,
    Map<String, dynamic>? fallbackCatalogData,
    List<String>? tamanhosHint,
    int quantidade = 0,
  }) {
    var variacoes = <String, dynamic>{};
    Map<String, dynamic> extra = {};
    var tamanhos = List<String>.from(tamanhosHint ?? []);

    void absorb(Map<String, dynamic> src) {
      if (src.isEmpty) return;
      variacoes = mesclarVariacoesComPrioridadePush(base: variacoes, push: src);
    }

    if (baseline != null && produtoFormBaselineHadGrade(baseline)) {
      final basePayload = produtoFormBaselineGradePayload(baseline);
      absorb(basePayload.variacoes);
      if (extra.isEmpty && basePayload.variacoesExtraTipo != null) {
        extra = Map<String, dynamic>.from(basePayload.variacoesExtraTipo!);
      }
      if (tamanhos.isEmpty && basePayload.tamanhos.isNotEmpty) {
        tamanhos = List<String>.from(basePayload.tamanhos);
      }
      if (variacoes.isEmpty && basePayload.estoquePorTamanho.isNotEmpty) {
        absorb(produtoFormVariacoesFromEstoquePorTamanho(
          basePayload.estoquePorTamanho,
        ));
      }
    }

    if (existingEstoqueData != null) {
      absorb(mapFromDynamic(existingEstoqueData['variacoes']));
      if (extra.isEmpty) {
        extra.addAll(mapFromDynamic(existingEstoqueData['variacoesExtraTipo']));
      }
      if (tamanhos.isEmpty) {
        tamanhos.addAll(tamanhosFromDynamic(existingEstoqueData['tamanhos']));
      }
      final estoqueRemoto =
          estoqueFromDynamic(existingEstoqueData['estoquePorTamanho']);
      if (variacoes.isEmpty && estoqueRemoto.isNotEmpty) {
        absorb(produtoFormVariacoesFromEstoquePorTamanho(estoqueRemoto));
      }
    }

    if (localUnfilteredVariacoes != null) {
      absorb(localUnfilteredVariacoes);
    }

    if (fallbackCatalogData != null) {
      absorb(mapFromDynamic(fallbackCatalogData['variacoes']));
      if (extra.isEmpty) {
        extra.addAll(mapFromDynamic(fallbackCatalogData['variacoesExtraTipo']));
      }
      if (tamanhos.isEmpty) {
        tamanhos.addAll(tamanhosFromDynamic(fallbackCatalogData['tamanhos']));
      }
      final estoqueCat =
          estoqueFromDynamic(fallbackCatalogData['estoquePorTamanho']);
      if (variacoes.isEmpty && estoqueCat.isNotEmpty) {
        absorb(produtoFormVariacoesFromEstoquePorTamanho(estoqueCat));
      }
    }

    if (variacoes.isEmpty &&
        (extra.isNotEmpty || tamanhos.isNotEmpty)) {
      final estoqueHint = existingEstoqueData != null
          ? estoqueFromDynamic(existingEstoqueData['estoquePorTamanho'])
          : <String, int>{};
      final rebuilt = reconstructVariacoesFromSignals(
        variacoesExtraTipo: extra,
        tamanhos: tamanhos,
        estoquePorTamanhoHint: estoqueHint,
        quantidade: quantidade,
      );
      absorb(rebuilt);
    }

    final estoqueHints = <String, int>{};
    if (baseline != null && produtoFormBaselineHadGrade(baseline)) {
      estoqueHints.addAll(
        produtoFormBaselineGradePayload(baseline).estoquePorTamanho,
      );
    }
    if (existingEstoqueData != null) {
      estoqueHints.addAll(
        estoqueFromDynamic(existingEstoqueData['estoquePorTamanho']),
      );
    }
    if (fallbackCatalogData != null) {
      estoqueHints.addAll(
        estoqueFromDynamic(fallbackCatalogData['estoquePorTamanho']),
      );
    }
    if (estoqueHints.isNotEmpty) {
      final fromEstoque =
          produtoFormVariacoesFromEstoquePorTamanho(estoqueHints);
      for (final entry in fromEstoque.entries) {
        if (!variacoes.containsKey(entry.key)) {
          variacoes[entry.key] = _cloneVariacaoCelula(entry.value);
        }
      }
    }

    return variacoes;
  }

  static List<String> _tamanhosFromVariacoesOuFontes({
    required Map<String, dynamic> variacoes,
    required List<String> tamanhosAtuais,
    ProdutoFormGradeBaseline? baseline,
    Map<String, dynamic>? existingEstoqueData,
    List<String>? localUnfilteredTamanhos,
    Map<String, dynamic>? fallbackCatalogData,
  }) {
    final out = <String>{
      ...tamanhosAtuais,
      ...produtoFormTamanhosFromVariacoes(variacoes),
    };
    if (baseline != null && baseline.tamanhos.isNotEmpty) {
      out.addAll(baseline.tamanhos);
    }
    if (existingEstoqueData != null) {
      out.addAll(tamanhosFromDynamic(existingEstoqueData['tamanhos']));
    }
    if (localUnfilteredTamanhos != null) {
      out.addAll(localUnfilteredTamanhos);
    }
    if (fallbackCatalogData != null) {
      out.addAll(tamanhosFromDynamic(fallbackCatalogData['tamanhos']));
    }
    return out.toList();
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

  /// Quantidade total a partir de [variacoes] (soma de todas as células).
  @visibleForTesting
  static int quantidadeTotalFromVariacoes(Map<String, dynamic> variacoes) {
    var total = 0;
    for (final tam in variacoes.values) {
      if (tam is! Map) continue;
      for (final cell in tam.values) {
        total += ProdutoVariacaoExtra.somarCelula(cell);
      }
    }
    return total;
  }

  @visibleForTesting
  static bool variacoesQuantidadesIguais(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    if (a.length != b.length) return false;
    for (final te in a.entries) {
      final bm = b[te.key];
      if (bm is! Map) return false;
      final am = te.value;
      if (am is! Map) return false;
      if (am.length != bm.length) return false;
      for (final ce in am.entries) {
        final bv = bm[ce.key];
        if (ProdutoVariacaoExtra.somarCelula(ce.value) !=
            ProdutoVariacaoExtra.somarCelula(bv)) {
          return false;
        }
      }
    }
    return true;
  }

  static Map<String, double>? _resolverPrecoPorTamanhoAusente(
    Map<String, double>? preco,
    Map<String, dynamic>? existingEstoqueData,
  ) {
    if (preco != null && preco.isNotEmpty) return preco;
    if (existingEstoqueData == null) return preco;
    final rawPpt = existingEstoqueData['precoPorTamanho'];
    if (rawPpt is Map && rawPpt.isNotEmpty) {
      return rawPpt.map(
        (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
      );
    }
    return preco;
  }

  static void _preencherMetadadosGradeAusentes({
    required Map<String, dynamic> extra,
    required List<String> tamanhos,
    Map<String, dynamic>? localUnfilteredExtra,
    List<String>? localUnfilteredTamanhos,
    ProdutoFormGradeBaseline? baseline,
    Map<String, dynamic>? existingEstoqueData,
    Map<String, dynamic>? fallbackCatalogData,
  }) {
    if (extra.isEmpty && localUnfilteredExtra != null && localUnfilteredExtra.isNotEmpty) {
      extra.addAll(localUnfilteredExtra);
    }
    if (tamanhos.isEmpty &&
        localUnfilteredTamanhos != null &&
        localUnfilteredTamanhos.isNotEmpty) {
      tamanhos.addAll(localUnfilteredTamanhos);
    }
    if (baseline != null && produtoFormBaselineHadGrade(baseline)) {
      final base = produtoFormBaselineGradePayload(baseline);
      if (extra.isEmpty && base.variacoesExtraTipo != null) {
        extra.addAll(base.variacoesExtraTipo!);
      }
      if (tamanhos.isEmpty && base.tamanhos.isNotEmpty) {
        tamanhos.addAll(base.tamanhos);
      }
    }
    if (existingEstoqueData != null) {
      if (extra.isEmpty) {
        extra.addAll(mapFromDynamic(existingEstoqueData['variacoesExtraTipo']));
      }
      if (tamanhos.isEmpty) {
        tamanhos.addAll(tamanhosFromDynamic(existingEstoqueData['tamanhos']));
      }
    }
    if (fallbackCatalogData != null) {
      if (extra.isEmpty) {
        extra.addAll(mapFromDynamic(fallbackCatalogData['variacoesExtraTipo']));
      }
      if (tamanhos.isEmpty) {
        tamanhos.addAll(tamanhosFromDynamic(fallbackCatalogData['tamanhos']));
      }
    }
  }

  static ProdutoEstoqueGradePushResult _resultadoPushVariacoesAutoritativo({
    required String lojaId,
    required String produtoId,
    required Map<String, dynamic> variacoesPush,
    required Map<String, dynamic> variacoesExtraPush,
    required List<String> tamanhosPush,
    Map<String, double>? precoPorTamanhoPush,
    Map<String, dynamic>? localUnfilteredVariacoes,
    Map<String, dynamic>? localUnfilteredExtra,
    List<String>? localUnfilteredTamanhos,
    ProdutoFormGradeBaseline? baseline,
    Map<String, dynamic>? existingEstoqueData,
    Map<String, dynamic>? fallbackCatalogData,
    required int quantidade,
  }) {
    final preservacao = _coletarVariacoesPreservacao(
      baseline: baseline,
      existingEstoqueData: existingEstoqueData,
      localUnfilteredVariacoes: localUnfilteredVariacoes,
      fallbackCatalogData: fallbackCatalogData,
      tamanhosHint: tamanhosPush,
      quantidade: quantidade,
    );
    var variacoes = mesclarVariacoesComPrioridadePush(
      base: preservacao,
      push: variacoesPush,
    );
    var extra = Map<String, dynamic>.from(variacoesExtraPush);
    var tamanhos = List<String>.from(tamanhosPush);
    _preencherMetadadosGradeAusentes(
      extra: extra,
      tamanhos: tamanhos,
      localUnfilteredExtra: localUnfilteredExtra,
      localUnfilteredTamanhos: localUnfilteredTamanhos,
      baseline: baseline,
      existingEstoqueData: existingEstoqueData,
      fallbackCatalogData: fallbackCatalogData,
    );
    tamanhos = _tamanhosFromVariacoesOuFontes(
      variacoes: variacoes,
      tamanhosAtuais: tamanhos,
      baseline: baseline,
      existingEstoqueData: existingEstoqueData,
      localUnfilteredTamanhos: localUnfilteredTamanhos,
      fallbackCatalogData: fallbackCatalogData,
    );
    final estoque = _estoqueFromVariacoes(variacoes);
    final preco = _resolverPrecoPorTamanhoAusente(
      precoPorTamanhoPush,
      existingEstoqueData,
    );
    final qtyTotal = quantidadeTotalFromVariacoes(variacoes);
    _logGradeCanonical(
      'PRODUTO_GRADE_CANONICAL_PRESERVE',
      lojaId: lojaId,
      produtoId: produtoId,
      origem: 'push_variacoes_tela',
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
      quantidade: qtyTotal,
    );
    return ProdutoEstoqueGradePushResult(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoque,
      tamanhos: tamanhos,
      precoPorTamanho: preco,
      origem: 'push_variacoes_tela',
      acao: 'preserve',
    );
  }

  static ProdutoEstoqueGradePushResult _resultadoPushEstoqueAutoritativo({
    required String lojaId,
    required String produtoId,
    required Map<String, int> estoquePorTamPush,
    required Map<String, dynamic> variacoesExtraPush,
    required List<String> tamanhosPush,
    Map<String, double>? precoPorTamanhoPush,
    Map<String, int>? localUnfilteredEstoque,
    Map<String, dynamic>? localUnfilteredExtra,
    List<String>? localUnfilteredTamanhos,
    ProdutoFormGradeBaseline? baseline,
    Map<String, dynamic>? existingEstoqueData,
    Map<String, dynamic>? fallbackCatalogData,
    required int quantidade,
  }) {
    final preservacaoVar = _coletarVariacoesPreservacao(
      baseline: baseline,
      existingEstoqueData: existingEstoqueData,
      localUnfilteredVariacoes: localUnfilteredEstoque == null
          ? null
          : produtoFormVariacoesFromEstoquePorTamanho(localUnfilteredEstoque),
      fallbackCatalogData: fallbackCatalogData,
      tamanhosHint: tamanhosPush,
      quantidade: quantidade,
    );
    final pushVar = produtoFormVariacoesFromEstoquePorTamanho(estoquePorTamPush);
    var variacoes = mesclarVariacoesComPrioridadePush(
      base: preservacaoVar,
      push: pushVar,
    );
    var extra = Map<String, dynamic>.from(variacoesExtraPush);
    var tamanhos = List<String>.from(tamanhosPush);
    _preencherMetadadosGradeAusentes(
      extra: extra,
      tamanhos: tamanhos,
      localUnfilteredExtra: localUnfilteredExtra,
      localUnfilteredTamanhos: localUnfilteredTamanhos,
      baseline: baseline,
      existingEstoqueData: existingEstoqueData,
      fallbackCatalogData: fallbackCatalogData,
    );
    tamanhos = _tamanhosFromVariacoesOuFontes(
      variacoes: variacoes,
      tamanhosAtuais: tamanhos,
      baseline: baseline,
      existingEstoqueData: existingEstoqueData,
      localUnfilteredTamanhos: localUnfilteredTamanhos,
      fallbackCatalogData: fallbackCatalogData,
    );
    final estoqueFinal = _estoqueFromVariacoes(variacoes);
    final preco = _resolverPrecoPorTamanhoAusente(
      precoPorTamanhoPush,
      existingEstoqueData,
    );
    final qtyTotal = quantidadeTotalFromVariacoes(variacoes);
    _logGradeCanonical(
      'PRODUTO_GRADE_CANONICAL_PRESERVE',
      lojaId: lojaId,
      produtoId: produtoId,
      origem: 'push_estoque_tela',
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoqueFinal,
      tamanhos: tamanhos,
      quantidade: qtyTotal,
    );
    return ProdutoEstoqueGradePushResult(
      variacoes: variacoes,
      variacoesExtraTipo: extra,
      estoquePorTamanho: estoqueFinal,
      tamanhos: tamanhos,
      precoPorTamanho: preco,
      origem: 'push_estoque_tela',
      acao: 'preserve',
    );
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
  /// Prioridade: quantidade editada na tela (variacoes/estoque do push) →
  /// local não filtrado → baseline → remoto estoque → reconstrução
  /// (live/draft só como fallback de metadados/reconstrução).
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
    // Quantidade editada na tela sempre vence baseline/remoto.
    if (variacoesPush.isNotEmpty) {
      return _resultadoPushVariacoesAutoritativo(
        lojaId: lojaId,
        produtoId: produtoId,
        variacoesPush: variacoesPush,
        variacoesExtraPush: variacoesExtraPush,
        tamanhosPush: tamanhosPush,
        precoPorTamanhoPush: precoPorTamanhoPush,
        localUnfilteredVariacoes: localUnfilteredVariacoes,
        localUnfilteredExtra: localUnfilteredExtra,
        localUnfilteredTamanhos: localUnfilteredTamanhos,
        baseline: baseline,
        existingEstoqueData: existingEstoqueData,
        fallbackCatalogData: fallbackCatalogData,
        quantidade: quantidade,
      );
    }
    if (estoquePorTamPush.isNotEmpty) {
      return _resultadoPushEstoqueAutoritativo(
        lojaId: lojaId,
        produtoId: produtoId,
        estoquePorTamPush: estoquePorTamPush,
        variacoesExtraPush: variacoesExtraPush,
        tamanhosPush: tamanhosPush,
        precoPorTamanhoPush: precoPorTamanhoPush,
        localUnfilteredEstoque: localUnfilteredEstoque,
        localUnfilteredExtra: localUnfilteredExtra,
        localUnfilteredTamanhos: localUnfilteredTamanhos,
        baseline: baseline,
        existingEstoqueData: existingEstoqueData,
        fallbackCatalogData: fallbackCatalogData,
        quantidade: quantidade,
      );
    }

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

    if (variacoes.isNotEmpty) {
      estoque = _estoqueFromVariacoes(variacoes);
    } else if (estoque.isNotEmpty) {
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
      if (localCompleta) {
        final localV = mapFromDynamic(local.variacoes);
        final remoteV = mapFromDynamic(remoteData['variacoes']);
        if (variacoesQuantidadesIguais(localV, remoteV)) {
          return const ProdutoEstoqueGradeRehydrateResult(
            aplicarGradeRemota: true,
          );
        }
        if (variacoesLocalIsSubsetOfRemote(localV, remoteV)) {
          final merged = mesclarVariacoesComPrioridadePush(
            base: remoteV,
            push: localV,
          );
          final estoqueMerged = _estoqueFromVariacoes(merged);
          final tamanhosMerged = _tamanhosFromVariacoesOuFontes(
            variacoes: merged,
            tamanhosAtuais: tamanhosFromDynamic(remoteData['tamanhos']),
            baseline: baseline,
            existingEstoqueData: remoteData,
            localUnfilteredTamanhos: List<String>.from(local.tamanhos),
            fallbackCatalogData: fallbackCatalogData,
          );
          Map<String, dynamic>? extraMerged =
              mapFromDynamic(remoteData['variacoesExtraTipo']);
          if (extraMerged.isEmpty && local.variacoesExtraTipo != null) {
            extraMerged = Map<String, dynamic>.from(local.variacoesExtraTipo!);
          }
          return ProdutoEstoqueGradeRehydrateResult(
            aplicarGradeRemota: false,
            variacoes: merged,
            variacoesExtraTipo: extraMerged.isEmpty ? null : extraMerged,
            estoquePorTamanho: estoqueMerged,
            tamanhos: tamanhosMerged,
            precoPorTamanho: local.precoPorTamanho == null
                ? null
                : Map<String, double>.from(local.precoPorTamanho!),
          );
        }
        if (variacoesMesmasChaves(localV, remoteV)) {
          return ProdutoEstoqueGradeRehydrateResult(
            aplicarGradeRemota: false,
            aviso: avisoGradeRemotaIncompleta,
            variacoes: localV,
            variacoesExtraTipo: local.variacoesExtraTipo == null
                ? null
                : Map<String, dynamic>.from(local.variacoesExtraTipo!),
            estoquePorTamanho: Map<String, int>.from(local.estoquePorTamanho),
            tamanhos: List<String>.from(local.tamanhos),
            precoPorTamanho: local.precoPorTamanho == null
                ? null
                : Map<String, double>.from(local.precoPorTamanho!),
          );
        }
      }
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
