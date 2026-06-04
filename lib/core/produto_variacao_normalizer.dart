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

/// Linha da grade do formulário (valores em texto).
typedef ProdutoVariacaoGradeRow = Map<String, String>;

abstract final class ProdutoVariacaoNormalizer {
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

  /// Monta `variacoes` no formato tamanho → cor → qtd (sem eixo extra) a partir de estoque por tamanho.
  static Map<String, dynamic> rebuildVariacoesFromEstoquePorTamanho(
    Map<String, int> estoquePorTamanho, {
    bool includeZeroQty = false,
  }) {
    final out = <String, dynamic>{};
    for (final e in estoquePorTamanho.entries) {
      final tam = e.key.trim();
      if (tam.isEmpty) continue;
      final qtd = e.value;
      if (qtd <= 0 && !includeZeroQty) continue;
      final chaveT = tam;
      out[chaveT] = {
        'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: qtd},
      };
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

  /// Garante mapa `variacoes` para o catálogo/Hive quando só existe estoque legado.
  static Map<String, dynamic>? ensureVariacoesMap({
    Map<String, dynamic>? variacoes,
    Map<String, int>? estoquePorTamanho,
    bool includeZeroQty = false,
  }) {
    if (variacoes != null && variacoes.isNotEmpty) return variacoes;
    final est = estoquePorTamanho ?? const {};
    if (est.isEmpty) return variacoes;
    final rebuilt = rebuildVariacoesFromEstoquePorTamanho(
      est,
      includeZeroQty: includeZeroQty,
    );
    return rebuilt.isEmpty ? variacoes : rebuilt;
  }

  /// Normaliza a partir de um [Produto] (Hive/admin).
  static ProdutoVariacaoNormalizado normalizedFromProduto(Produto p) {
    final variacoesExistentes = p.variacoes;
    if (variacoesExistentes != null && variacoesExistentes.isNotEmpty) {
      final est = p.estoquePorTamanho.isNotEmpty
          ? Map<String, int>.from(p.estoquePorTamanho)
          : estoquePorTamanhoFromVariacoes(variacoesExistentes);
      return ProdutoVariacaoNormalizado(
        variacoes: Map<String, dynamic>.from(variacoesExistentes),
        variacoesExtraTipo: p.variacoesExtraTipo == null
            ? null
            : Map<String, dynamic>.from(p.variacoesExtraTipo!),
        estoquePorTamanho: est,
        hydratedFromLegacy: false,
      );
    }

    var estoque = Map<String, int>.from(p.estoquePorTamanho);
    if (estoque.isEmpty && p.tamanhos.isNotEmpty) {
      for (final t in p.tamanhos) {
        final key = t.trim();
        if (key.isEmpty) continue;
        estoque.putIfAbsent(key, () => 0);
      }
    }

    if (estoque.isNotEmpty) {
      final vars = rebuildVariacoesFromEstoquePorTamanho(estoque);
      return ProdutoVariacaoNormalizado(
        variacoes: vars,
        variacoesExtraTipo: null,
        estoquePorTamanho: estoque,
        hydratedFromLegacy: vars.isNotEmpty,
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
    if (n.variacoes.isNotEmpty) {
      p.variacoes = Map<String, dynamic>.from(n.variacoes);
      if (n.variacoesExtraTipo != null) {
        p.variacoesExtraTipo = Map<String, dynamic>.from(n.variacoesExtraTipo!);
      }
    }
    if (n.estoquePorTamanho.isNotEmpty) {
      p.estoquePorTamanho = Map<String, int>.from(n.estoquePorTamanho);
    }
    return n.hydratedFromLegacy;
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
      final est = p.estoquePorTamanho;
      final chaves = est.isNotEmpty
          ? est.keys.map((k) => k.toString()).toList()
          : p.tamanhos.map((t) => t.toString()).toList();
      for (final tam in chaves) {
        final key = tam.trim();
        if (key.isEmpty) continue;
        rows.add({
          'tamanho': key,
          'cor': '',
          'extraTipo': '',
          'extraValor': '',
          'qtd': (est[key] ?? 0).toString(),
          'custo': '',
        });
      }
    }
    return rows;
  }

  /// Mapa de produto do catálogo (Firestore): garante `variacoes` para o seletor.
  static void applyToCatalogProductMap(Map<String, dynamic> m) {
    Map<String, int>? estoquePorTamanho;
    final estoqueTamRaw = m['estoquePorTamanho'];
    if (estoqueTamRaw is Map && estoqueTamRaw.isNotEmpty) {
      estoquePorTamanho = {};
      estoqueTamRaw.forEach((key, value) {
        final k = key.toString().trim();
        if (k.isEmpty) return;
        estoquePorTamanho![k] =
            ProdutoVariacaoExtra.valorFirestoreComoInt(value);
      });
      if (estoquePorTamanho.isEmpty) estoquePorTamanho = null;
    }

    Map<String, dynamic>? variacoes;
    final variacoesRaw = m['variacoes'];
    if (variacoesRaw is Map && variacoesRaw.isNotEmpty) {
      variacoes = Map<String, dynamic>.from(variacoesRaw);
    }

    final ensured = ensureVariacoesMap(
      variacoes: variacoes,
      estoquePorTamanho: estoquePorTamanho,
      includeZeroQty: true,
    );
    if (ensured != null && ensured.isNotEmpty) {
      m['variacoes'] = ensured;
    }
    if (estoquePorTamanho != null && estoquePorTamanho.isNotEmpty) {
      m['estoquePorTamanho'] = estoquePorTamanho;
    } else if (ensured != null && ensured.isNotEmpty) {
      m['estoquePorTamanho'] =
          estoquePorTamanhoFromVariacoes(ensured);
    }
  }
}
