// Normalização de variações: alinha lista de estoque, cadastro e catálogo.
// Reidrata `variacoes` a partir de `estoquePorTamanho` / `tamanhos` legados sem apagar dados.

import '../models/produto.dart';
import 'produto_variacao_extra.dart';

/// Resultado da normalização (variações + estoque por tamanho coerentes).
class ProdutoVariacaoNormalizado {
  const ProdutoVariacaoNormalizado({
    required this.variacoes,
    this.variacoesExtraTipo,
    required this.estoquePorTamanho,
    required this.hydratedFromLegacy,
  });

  final Map<String, dynamic> variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final Map<String, int> estoquePorTamanho;
  final bool hydratedFromLegacy;
}

/// Componentes de uma chave legada/composta em `estoquePorTamanho`.
class EstoqueChaveComposta {
  const EstoqueChaveComposta({
    required this.tamanho,
    this.cor = '',
    this.extraTipo = '',
    this.extraValor = '',
  });

  final String tamanho;
  final String cor;
  final String extraTipo;
  final String extraValor;
}

/// Linha da grade do formulário (valores em texto).
typedef ProdutoVariacaoGradeRow = Map<String, String>;

abstract final class ProdutoVariacaoNormalizer {
  static const _nestedQtyKeys = <String>[
    'quantidade',
    'qtd',
    'estoque',
    'saldo',
  ];

  static bool hasRepresentacaoVariacao({
    Map<String, dynamic>? variacoes,
    Map<String, int>? estoquePorTamanho,
    Map<String, dynamic>? variacoesExtraTipo,
    Map<String, double>? precoPorTamanho,
    Iterable<String>? tamanhos,
  }) {
    if (variacoes != null && variacoes.isNotEmpty) return true;
    if (estoquePorTamanho != null && estoquePorTamanho.isNotEmpty) return true;
    if (variacoesExtraTipo != null && variacoesExtraTipo.isNotEmpty) {
      return true;
    }
    if (precoPorTamanho != null && precoPorTamanho.isNotEmpty) return true;
    if (tamanhos != null && tamanhos.any((t) => t.trim().isNotEmpty)) return true;
    return false;
  }

  /// Decodifica chaves como `14`, `14|Prata`, `15/16|Prata`, `14|Prata|Letra|A`.
  static EstoqueChaveComposta parseChaveCompostaEstoque(String key) {
    final k = key.trim();
    if (k.isEmpty) {
      return const EstoqueChaveComposta(tamanho: '');
    }
    if (!k.contains('|')) {
      return EstoqueChaveComposta(tamanho: k);
    }
    final parts =
        k.split('|').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return const EstoqueChaveComposta(tamanho: '');
    }
    if (parts.length == 1) {
      return EstoqueChaveComposta(tamanho: parts[0]);
    }
    if (parts.length == 2) {
      return EstoqueChaveComposta(tamanho: parts[0], cor: parts[1]);
    }
    if (parts.length == 3) {
      return EstoqueChaveComposta(
        tamanho: parts[0],
        cor: parts[1],
        extraValor: parts[2],
      );
    }
    return EstoqueChaveComposta(
      tamanho: parts[0],
      cor: parts[1],
      extraTipo: parts[2],
      extraValor: parts[3],
    );
  }

  /// Codifica chave composta preservando cor/extra (não reduz ao tamanho).
  static String encodeChaveCompostaEstoque({
    required String tamanho,
    String cor = '',
    String extraTipo = '',
    String extraValor = '',
  }) {
    final t = tamanho.trim();
    if (t.isEmpty) return '';
    final c = cor.trim();
    final ev = extraValor.trim();
    final et = extraTipo.trim();
    if (c.isEmpty && ev.isEmpty) return t;
    if (ev.isEmpty) return '$t|$c';
    if (et.isNotEmpty) return '$t|$c|$et|$ev';
    return '$t|$c|$ev';
  }

  /// Parse robusto de `estoquePorTamanho` — preserva chaves originais (incl. compostas).
  static Map<String, int> parseEstoquePorTamanhoRaw(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, int>) {
      return Map<String, int>.from(raw);
    }
    if (raw is Map) {
      final parsed = <String, int>{};
      raw.forEach((key, value) {
        final k = key.toString().trim();
        if (k.isEmpty) return;
        parsed[k] = parseQuantidadeCelulaEstoque(value);
      });
      return parsed;
    }
    return {};
  }

  /// Quantidade numérica de um valor de estoque (escalar ou mapa aninhado).
  static int parseQuantidadeCelulaEstoque(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is Map) {
      for (final nestedKey in _nestedQtyKeys) {
        if (value.containsKey(nestedKey)) {
          return ProdutoVariacaoExtra.valorFirestoreComoInt(value[nestedKey]);
        }
      }
      return ProdutoVariacaoExtra.valorFirestoreComoInt(value);
    }
    return int.tryParse(value.toString().trim()) ?? 0;
  }

  static int somaEstoquePorTamanho(Map<String, int> estoque) {
    var s = 0;
    for (final v in estoque.values) {
      s += v;
    }
    return s;
  }

  static int somaVariacoesMap(Map<String, dynamic> variacoes) {
    return estoquePorTamanhoFromVariacoes(variacoes)
        .values
        .fold<int>(0, (a, b) => a + b);
  }

  static bool variacoesSemQuantidadeUtil(Map<String, dynamic>? variacoes) {
    if (variacoes == null || variacoes.isEmpty) return true;
    return somaVariacoesMap(variacoes) <= 0;
  }

  static bool estoqueTemQuantidadePositiva(Map<String, int> estoque) {
    return estoque.values.any((q) => q > 0);
  }

  static bool estoqueRawUsaChavesCompostas(Map<String, int> raw) {
    return raw.keys.any((k) => k.contains('|'));
  }

  static bool variacoesTemEstruturaRica(Map<String, dynamic> variacoes) {
    for (final tamEntry in variacoes.entries) {
      final cores = tamEntry.value;
      if (cores is! Map) continue;
      for (final corEntry in cores.entries) {
        final cor = corEntry.key.toString();
        if (cor != 'sem-cor' && cor.isNotEmpty) return true;
        final raw = corEntry.value;
        if (raw is Map && ProdutoVariacaoExtra.celulaTemExtrasNaoVazios(raw)) {
          return true;
        }
      }
    }
    return false;
  }

  static int lookupQuantidadeEstoqueRaw(
    Map<String, int> raw, {
    required String tamanho,
    String cor = '',
    String extraTipo = '',
    String extraValor = '',
  }) {
    final candidates = <String>{
      encodeChaveCompostaEstoque(
        tamanho: tamanho,
        cor: cor,
        extraTipo: extraTipo,
        extraValor: extraValor,
      ),
      if (cor.isNotEmpty)
        encodeChaveCompostaEstoque(tamanho: tamanho, cor: cor),
      tamanho.trim(),
    }..removeWhere((k) => k.isEmpty);
    for (final k in candidates) {
      if (raw.containsKey(k)) return raw[k]!;
    }
    return 0;
  }

  /// Monta `variacoes` + `variacoesExtraTipo` a partir do mapa bruto de estoque.
  static ({
    Map<String, dynamic> variacoes,
    Map<String, dynamic>? variacoesExtraTipo,
  }) rebuildVariacoesFromEstoqueRaw(
    Map<String, int> estoqueRaw, {
    bool includeZeroQty = false,
  }) {
    final variacoes = <String, dynamic>{};
    final tipos = <String, Map<String, Map<String, String>>>{};

    void addCelula({
      required String tamanho,
      required String cor,
      required String extraTipo,
      required String extraValor,
      required int qtd,
    }) {
      if (qtd <= 0 && !includeZeroQty) return;
      final chaveT = tamanho.isEmpty ? 'sem-tamanho' : tamanho;
      final chaveC = cor.isEmpty ? 'sem-cor' : cor;
      final mapaT = variacoes.putIfAbsent(chaveT, () => <String, dynamic>{});
      final mapaC =
          (mapaT[chaveC] as Map<String, dynamic>?) ?? <String, dynamic>{};
      if (extraValor.isEmpty) {
        mapaC[ProdutoVariacaoExtra.kSemExtraKey] = qtd;
      } else {
        mapaC[extraValor] = qtd;
        if (extraTipo.isNotEmpty) {
          final tm = tipos.putIfAbsent(chaveT, () => {});
          final cm = tm.putIfAbsent(chaveC, () => {});
          cm[extraValor] = extraTipo;
        }
      }
      mapaT[chaveC] = mapaC;
    }

    for (final e in estoqueRaw.entries) {
      final parsed = parseChaveCompostaEstoque(e.key);
      if (parsed.tamanho.isEmpty) continue;
      addCelula(
        tamanho: parsed.tamanho,
        cor: parsed.cor,
        extraTipo: parsed.extraTipo,
        extraValor: parsed.extraValor,
        qtd: e.value,
      );
    }

    Map<String, dynamic>? tiposOut;
    if (tipos.isNotEmpty) {
      tiposOut = tipos.map(
        (t, m) => MapEntry(
          t,
          m.map((c, em) => MapEntry(c, Map<String, dynamic>.from(em))),
        ),
      );
    }

    return (variacoes: variacoes, variacoesExtraTipo: tiposOut);
  }

  /// Preenche quantidades em `variacoes` existente a partir do estoque bruto (preserva cor/extra).
  static void mergeQuantidadeFromEstoqueRawIntoVariacoes(
    Map<String, dynamic> variacoes,
    Map<String, int> estoqueRaw,
  ) {
    for (final tamEntry in variacoes.entries) {
      final tamanho = tamEntry.key.toString();
      final mapaCores = tamEntry.value;
      if (mapaCores is! Map) continue;
      for (final corEntry in mapaCores.entries) {
        final cor = corEntry.key.toString();
        final raw = corEntry.value;
        final corDisp = cor == 'sem-cor' ? '' : cor;
        final tamDisp = tamanho == 'sem-tamanho' ? '' : tamanho;

        if (raw is num) {
          final q = lookupQuantidadeEstoqueRaw(
            estoqueRaw,
            tamanho: tamDisp,
            cor: corDisp,
          );
          if (q > 0) mapaCores[cor] = q;
          continue;
        }
        if (raw is! Map) continue;

        for (final ie in raw.entries) {
          if (ProdutoVariacaoExtra.isMetaKey(ie.key.toString())) continue;
          final ev = ie.key.toString();
          final evDisp =
              ProdutoVariacaoExtra.isSemExtraMapKey(ev) ? '' : ev;
          final q = lookupQuantidadeEstoqueRaw(
            estoqueRaw,
            tamanho: tamDisp,
            cor: corDisp,
            extraValor: evDisp,
          );
          if (q > 0) raw[ie.key] = q;
        }
      }
    }
  }

  /// Resumo por tamanho (soma) — só para derivar campo agregado, não para grade.
  static Map<String, int> estoquePorTamanhoResumoFromRaw(Map<String, int> raw) {
    final out = <String, int>{};
    for (final e in raw.entries) {
      final tam = parseChaveCompostaEstoque(e.key).tamanho;
      if (tam.isEmpty) continue;
      out[tam] = (out[tam] ?? 0) + e.value;
    }
    return out;
  }

  /// Soma por tamanho a partir do mapa `variacoes` (ignora `sem-tamanho`).
  static Map<String, int> estoquePorTamanhoFromVariacoes(
    Map<String, dynamic> variacoes,
  ) {
    final estoqueMapa = <String, int>{};
    for (final tamanho in variacoes.keys) {
      if (tamanho == 'sem-tamanho') continue;
      final mapaInterno = variacoes[tamanho];
      if (mapaInterno is! Map) continue;
      var total = 0;
      for (final v in mapaInterno.values) {
        total += ProdutoVariacaoExtra.somarCelula(v);
      }
      if (total > 0) estoqueMapa[tamanho.toString()] = total;
    }
    return estoqueMapa;
  }

  /// Estoque bruto coalescido (preserva chaves compostas).
  static Map<String, int> coalesceEstoquePorTamanho(Produto p) {
    var estoque = parseEstoquePorTamanhoRaw(p.estoquePorTamanho);
    if (estoqueTemQuantidadePositiva(estoque)) return estoque;

    final fromVars = p.variacoes == null || p.variacoes!.isEmpty
        ? const <String, int>{}
        : estoquePorTamanhoFromVariacoes(p.variacoes!);
    if (estoqueTemQuantidadePositiva(fromVars)) {
      return fromVars;
    }

    if (estoque.isNotEmpty) return estoque;
    if (fromVars.isNotEmpty) return fromVars;

    if (p.tamanhos.isNotEmpty) {
      for (final t in p.tamanhos) {
        final key = t.trim();
        if (key.isEmpty) continue;
        estoque.putIfAbsent(key, () => 0);
      }
    }
    return estoque;
  }

  static Map<String, dynamic>? ensureVariacoesMap({
    Map<String, dynamic>? variacoes,
    Map<String, int>? estoquePorTamanho,
    bool includeZeroQty = false,
  }) {
    final est = estoquePorTamanho ?? const {};
    final vars = variacoes;
    final varsSemQtd = vars != null && vars.isNotEmpty && variacoesSemQuantidadeUtil(vars);
    final estComQtd = estoqueTemQuantidadePositiva(est);

    if (vars != null &&
        vars.isNotEmpty &&
        variacoesSemQuantidadeUtil(vars) &&
        estComQtd) {
      if (variacoesTemEstruturaRica(vars)) {
        final merged = Map<String, dynamic>.from(vars);
        mergeQuantidadeFromEstoqueRawIntoVariacoes(merged, est);
        return merged;
      }
      final rebuilt = rebuildVariacoesFromEstoqueRaw(
        est,
        includeZeroQty: includeZeroQty,
      );
      return rebuilt.variacoes.isEmpty ? vars : rebuilt.variacoes;
    }

    if (vars != null && vars.isNotEmpty && !varsSemQtd) return vars;

    if (est.isEmpty) return vars;
    final rebuilt = rebuildVariacoesFromEstoqueRaw(
      est,
      includeZeroQty: includeZeroQty,
    );
    return rebuilt.variacoes.isEmpty ? vars : rebuilt.variacoes;
  }

  static Map<String, dynamic>? ensureVariacoesExtraTipoMap({
    Map<String, dynamic>? variacoesExtraTipo,
    Map<String, int>? estoquePorTamanho,
    Map<String, dynamic>? variacoes,
    bool includeZeroQty = false,
  }) {
    if (variacoesExtraTipo != null && variacoesExtraTipo.isNotEmpty) {
      return variacoesExtraTipo;
    }
    final est = estoquePorTamanho ?? const {};
    if (est.isEmpty || !estoqueRawUsaChavesCompostas(est)) return variacoesExtraTipo;
    final rebuilt = rebuildVariacoesFromEstoqueRaw(
      est,
      includeZeroQty: includeZeroQty,
    );
    return rebuilt.variacoesExtraTipo;
  }

  /// Normaliza a partir de um [Produto] (Hive/admin).
  static ProdutoVariacaoNormalizado normalizedFromProduto(Produto p) {
    final estoqueRaw = coalesceEstoquePorTamanho(p);
    final variacoesExistentes = p.variacoes;

    if (variacoesExistentes != null && variacoesExistentes.isNotEmpty) {
      final varsSemQtd = variacoesSemQuantidadeUtil(variacoesExistentes);
      final estPositivo = estoqueTemQuantidadePositiva(estoqueRaw);

      if (varsSemQtd && estPositivo) {
        if (variacoesTemEstruturaRica(variacoesExistentes)) {
          final merged = Map<String, dynamic>.from(variacoesExistentes);
          mergeQuantidadeFromEstoqueRawIntoVariacoes(merged, estoqueRaw);
          return ProdutoVariacaoNormalizado(
            variacoes: merged,
            variacoesExtraTipo: p.variacoesExtraTipo == null
                ? null
                : Map<String, dynamic>.from(p.variacoesExtraTipo!),
            estoquePorTamanho: estoqueRaw,
            hydratedFromLegacy: true,
          );
        }
        final rebuilt = rebuildVariacoesFromEstoqueRaw(estoqueRaw);
        return ProdutoVariacaoNormalizado(
          variacoes: rebuilt.variacoes,
          variacoesExtraTipo: rebuilt.variacoesExtraTipo ??
              (p.variacoesExtraTipo == null
                  ? null
                  : Map<String, dynamic>.from(p.variacoesExtraTipo!)),
          estoquePorTamanho: estoqueRaw,
          hydratedFromLegacy: true,
        );
      }

      final estResumo = estoqueTemQuantidadePositiva(estoqueRaw)
          ? estoqueRaw
          : estoquePorTamanhoFromVariacoes(variacoesExistentes);
      return ProdutoVariacaoNormalizado(
        variacoes: Map<String, dynamic>.from(variacoesExistentes),
        variacoesExtraTipo: p.variacoesExtraTipo == null
            ? null
            : Map<String, dynamic>.from(p.variacoesExtraTipo!),
        estoquePorTamanho: estResumo,
        hydratedFromLegacy: false,
      );
    }

    if (estoqueRaw.isNotEmpty) {
      final rebuilt = rebuildVariacoesFromEstoqueRaw(
        estoqueRaw,
        includeZeroQty: !estoqueTemQuantidadePositiva(estoqueRaw),
      );
      return ProdutoVariacaoNormalizado(
        variacoes: rebuilt.variacoes,
        variacoesExtraTipo: rebuilt.variacoesExtraTipo,
        estoquePorTamanho: estoqueRaw,
        hydratedFromLegacy:
            rebuilt.variacoes.isNotEmpty ||
            !estoqueTemQuantidadePositiva(estoqueRaw),
      );
    }

    return ProdutoVariacaoNormalizado(
      variacoes: const {},
      variacoesExtraTipo: null,
      estoquePorTamanho: const {},
      hydratedFromLegacy: false,
    );
  }

  /// Aplica normalização no produto (preenche `variacoes` se só houver legado).
  static bool applyToProduto(Produto p) {
    final n = normalizedFromProduto(p);
    if (!n.hydratedFromLegacy && n.variacoes.isEmpty) return false;

    final varsSemQtd =
        p.variacoes != null && p.variacoes!.isNotEmpty && variacoesSemQuantidadeUtil(p.variacoes!);
    final estPositivo = estoqueTemQuantidadePositiva(n.estoquePorTamanho);
    final deveAtualizarVariacoes = n.variacoes.isNotEmpty &&
        (n.hydratedFromLegacy || (varsSemQtd && estPositivo));

    if (deveAtualizarVariacoes) {
      p.variacoes = Map<String, dynamic>.from(n.variacoes);
      if (n.variacoesExtraTipo != null && n.variacoesExtraTipo!.isNotEmpty) {
        p.variacoesExtraTipo = Map<String, dynamic>.from(n.variacoesExtraTipo!);
      }
    }

    if (n.estoquePorTamanho.isNotEmpty &&
        (!estoqueTemQuantidadePositiva(parseEstoquePorTamanhoRaw(p.estoquePorTamanho)) ||
            estPositivo)) {
      p.estoquePorTamanho = Map<String, int>.from(n.estoquePorTamanho);
    }
    return n.hydratedFromLegacy || (varsSemQtd && estPositivo);
  }

  static String _precoTextoGrade(double? v) {
    if (v == null || v <= 0) return '';
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Linhas da grade do cadastro a partir do produto (variações completas ou legado).
  static List<ProdutoVariacaoGradeRow> gradeRowsFromProduto(Produto p) {
    final n = normalizedFromProduto(p);

    final rows = <ProdutoVariacaoGradeRow>[];
    final vet = n.variacoesExtraTipo;
    for (final tamanhoEntry in n.variacoes.entries) {
      final tamanho = tamanhoEntry.key;
      final mapaCores = tamanhoEntry.value;
      if (mapaCores is! Map) continue;
      for (final corEntry in mapaCores.entries) {
        final cor = corEntry.key;
        final raw = corEntry.value;
        String tipoPara(String ev) {
          if (vet == null) return '';
          final tm = vet[tamanho];
          if (tm is! Map) return '';
          final cm = tm[cor];
          if (cm is! Map) return '';
          for (final e in cm.entries) {
            if (ProdutoVariacaoExtra.keysMatch(e.key.toString(), ev)) {
              return e.value?.toString() ?? '';
            }
          }
          return '';
        }

        if (raw is num) {
          rows.add({
            'tamanho': tamanho == 'sem-tamanho' ? '' : tamanho,
            'cor': cor == 'sem-cor' ? '' : cor,
            'extraTipo': '',
            'extraValor': '',
            'qtd': raw.toInt().toString(),
            'custo': '',
          });
        } else if (raw is Map) {
          final custoCelula = ProdutoVariacaoExtra.custoUnitarioNaCelula(raw);
          final custoTexto = (custoCelula != null && custoCelula > 0)
              ? custoCelula.toStringAsFixed(2).replaceAll('.', ',')
              : '';
          for (final ie in raw.entries) {
            if (ProdutoVariacaoExtra.isMetaKey(ie.key.toString())) continue;
            final ev = ie.key.toString();
            final q = ie.value is num
                ? (ie.value as num).toInt()
                : int.tryParse(ie.value?.toString() ?? '') ?? 0;
            final evDisp =
                ProdutoVariacaoExtra.isSemExtraMapKey(ev) ? '' : ev;
            rows.add({
              'tamanho': tamanho == 'sem-tamanho' ? '' : tamanho,
              'cor': cor == 'sem-cor' ? '' : cor,
              'extraTipo': tipoPara(evDisp),
              'extraValor': evDisp,
              'qtd': q.toString(),
              'custo': custoTexto,
            });
          }
        }
      }
    }

    if (rows.isEmpty) {
      final est = n.estoquePorTamanho;
      final chaves = est.isNotEmpty
          ? est.keys.map((k) => k.toString()).toList()
          : p.tamanhos.map((t) => t.toString()).toList();
      for (final chave in chaves) {
        final key = chave.trim();
        if (key.isEmpty) continue;
        final parsed = parseChaveCompostaEstoque(key);
        final tam = parsed.tamanho.isEmpty ? key : parsed.tamanho;
        final precoTam = p.precoPorTamanho?[tam] ??
            p.precoPorTamanho?['sem-tamanho'];
        rows.add({
          'tamanho': tam,
          'cor': parsed.cor,
          'extraTipo': parsed.extraTipo,
          'extraValor': parsed.extraValor,
          'qtd': (est[key] ?? 0).toString(),
          'custo': _precoTextoGrade(precoTam),
        });
      }
    } else {
      _aplicarQuantidadeEstoqueNasLinhas(rows, n.estoquePorTamanho);
    }
    return rows;
  }

  /// Se a grade veio de `variacoes` com qtd 0, preenche a partir do estoque bruto.
  static void _aplicarQuantidadeEstoqueNasLinhas(
    List<ProdutoVariacaoGradeRow> rows,
    Map<String, int> estoqueRaw,
  ) {
    if (!estoqueTemQuantidadePositiva(estoqueRaw)) return;
    for (final row in rows) {
      final tam = (row['tamanho'] ?? '').trim();
      if (tam.isEmpty) continue;
      final qtdLinha = int.tryParse(row['qtd'] ?? '') ?? 0;
      if (qtdLinha > 0) continue;
      final qtdEstoque = lookupQuantidadeEstoqueRaw(
        estoqueRaw,
        tamanho: tam,
        cor: row['cor'] ?? '',
        extraTipo: row['extraTipo'] ?? '',
        extraValor: row['extraValor'] ?? '',
      );
      if (qtdEstoque > 0) {
        row['qtd'] = qtdEstoque.toString();
      }
    }
  }

  /// Mapa de produto do catálogo (Firestore): garante `variacoes` para o seletor.
  static void applyToCatalogProductMap(Map<String, dynamic> m) {
    final estoqueRaw = parseEstoquePorTamanhoRaw(m['estoquePorTamanho']);
    final estoqueFinal = estoqueRaw.isEmpty ? null : estoqueRaw;

    Map<String, dynamic>? variacoes;
    final variacoesRaw = m['variacoes'];
    if (variacoesRaw is Map && variacoesRaw.isNotEmpty) {
      variacoes = Map<String, dynamic>.from(variacoesRaw);
    }

    Map<String, dynamic>? variacoesExtraTipo;
    final vetRaw = m['variacoesExtraTipo'];
    if (vetRaw is Map && vetRaw.isNotEmpty) {
      variacoesExtraTipo = Map<String, dynamic>.from(vetRaw);
    }

    final includeZero = !estoqueTemQuantidadePositiva(estoqueFinal ?? const {});

    final ensured = ensureVariacoesMap(
      variacoes: variacoes,
      estoquePorTamanho: estoqueFinal,
      includeZeroQty: includeZero,
    );
    if (ensured != null && ensured.isNotEmpty) {
      m['variacoes'] = ensured;
    }

    final ensuredExtra = ensureVariacoesExtraTipoMap(
      variacoesExtraTipo: variacoesExtraTipo,
      estoquePorTamanho: estoqueFinal,
      variacoes: ensured ?? variacoes,
      includeZeroQty: includeZero,
    );
    if (ensuredExtra != null && ensuredExtra.isNotEmpty) {
      m['variacoesExtraTipo'] = ensuredExtra;
    }

    if (estoqueFinal != null && estoqueFinal.isNotEmpty) {
      m['estoquePorTamanho'] = estoqueFinal;
    } else if (ensured != null && ensured.isNotEmpty) {
      m['estoquePorTamanho'] = estoquePorTamanhoFromVariacoes(ensured);
    }
  }
}
