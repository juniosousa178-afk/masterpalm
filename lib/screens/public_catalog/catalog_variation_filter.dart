// Filtro do catálogo público por tamanho/medida e cor das variações (Firestore → mapa variacoes).

import '../../core/produto_variacao_extra.dart';
import 'catalog_estoque_helper.dart';

/// Utilitários para filtrar produtos por variação (ex.: anel 16, colar 45 cm, blusa M + cor rosa).
class CatalogVariationFilter {
  CatalogVariationFilter._();

  static String norm(String s) {
    var t = s.toLowerCase().trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  /// Compara chaves de tamanho/cor com tolerância (espaços, caixa): "45 cm" ≈ "45cm".
  static bool keysMatch(String a, String b) {
    final na = norm(a);
    final nb = norm(b);
    if (na == nb) return true;
    final ca = na.replaceAll(' ', '');
    final cb = nb.replaceAll(' ', '');
    return ca.isNotEmpty && ca == cb;
  }

  static bool _positive(dynamic q) =>
      ProdutoVariacaoExtra.somarCelula(q) > 0;

  static bool _extraMatchPositive(dynamic cell, String exW) {
    if (cell is! Map) return false;
    for (final e in cell.entries) {
      if (!keysMatch(e.key.toString(), exW)) continue;
      if (CatalogEstoqueHelper.parseQtd(e.value) > 0) return true;
    }
    return false;
  }

  /// Inclui o produto se não houver filtro de variação ou se existir estoque na combinação pedida.
  static bool produtoMatches(
    Map<String, dynamic> p, {
    String? tamanho,
    String? cor,
    String? variacaoExtra,
  }) {
    final tamW = tamanho?.trim();
    final corW = cor?.trim();
    final exW = variacaoExtra?.trim();
    if ((tamW == null || tamW.isEmpty) &&
        (corW == null || corW.isEmpty) &&
        (exW == null || exW.isEmpty)) {
      return true;
    }

    final variacoes = p['variacoes'];
    if (variacoes is Map && variacoes.isNotEmpty) {
      if (exW != null &&
          exW.isNotEmpty &&
          (tamW == null || tamW.isEmpty) &&
          (corW == null || corW.isEmpty)) {
        for (final cores in variacoes.values) {
          if (cores is! Map) continue;
          for (final cell in cores.values) {
            if (_extraMatchPositive(cell, exW)) return true;
          }
        }
        return false;
      }

      if (tamW != null &&
          tamW.isNotEmpty &&
          corW != null &&
          corW.isNotEmpty) {
        for (final e in variacoes.entries) {
          if (!keysMatch(e.key.toString(), tamW)) continue;
          final mapa = e.value;
          if (mapa is! Map) continue;
          for (final ck in mapa.keys) {
            if (!keysMatch(ck.toString(), corW)) continue;
            final cell = mapa[ck];
            if (exW != null && exW.isNotEmpty) {
              if (ProdutoVariacaoExtra.quantidadeNaCelula(cell, exW) > 0) {
                return true;
              }
            } else if (_positive(cell)) {
              return true;
            }
          }
        }
        return false;
      }
      if (tamW != null && tamW.isNotEmpty) {
        for (final e in variacoes.entries) {
          if (!keysMatch(e.key.toString(), tamW)) continue;
          final mapa = e.value;
          if (mapa is Map) {
            for (final cell in mapa.values) {
              if (exW != null && exW.isNotEmpty) {
                if (_extraMatchPositive(cell, exW)) return true;
              } else if (_positive(cell)) {
                return true;
              }
            }
          }
        }
        return false;
      }
      if (corW != null && corW.isNotEmpty) {
        for (final e in variacoes.values) {
          if (e is! Map) continue;
          for (final ck in e.keys) {
            if (!keysMatch(ck.toString(), corW)) continue;
            final cell = e[ck];
            if (exW != null && exW.isNotEmpty) {
              if (_extraMatchPositive(cell, exW)) return true;
            } else if (_positive(cell)) {
              return true;
            }
          }
        }
        return false;
      }
    }

    final ept = p['estoquePorTamanho'];
    final epc = p['estoquePorCor'];

    if (tamW != null &&
        tamW.isNotEmpty &&
        corW != null &&
        corW.isNotEmpty) {
      if (ept is Map) {
        for (final k in ept.keys) {
          if (!keysMatch(k.toString(), tamW)) continue;
          if (!_positive(ept[k])) continue;
          if (epc is Map) {
            for (final ck in epc.keys) {
              if (keysMatch(ck.toString(), corW) && _positive(epc[ck])) {
                return true;
              }
            }
          }
        }
      }
      return false;
    }

    if (tamW != null && tamW.isNotEmpty && ept is Map) {
      for (final k in ept.keys) {
        if (keysMatch(k.toString(), tamW) && _positive(ept[k])) {
          return true;
        }
      }
      return false;
    }

    if (corW != null && corW.isNotEmpty && epc is Map) {
      for (final ck in epc.keys) {
        if (keysMatch(ck.toString(), corW) && _positive(epc[ck])) {
          return true;
        }
      }
    }

    return false;
  }

  static List<String> coletarTamanhos(List<Map<String, dynamic>> produtos) {
    final set = <String>{};
    for (final p in produtos) {
      final v = p['variacoes'];
      if (v is Map && v.isNotEmpty) {
        for (final k in v.keys) {
          final s = k.toString().trim();
          if (s.isEmpty) continue;
          set.add(s);
        }
      }
      final ept = p['estoquePorTamanho'];
      if (ept is Map) {
        for (final k in ept.keys) {
          if (CatalogEstoqueHelper.parseQtd(ept[k]) > 0) {
            set.add(k.toString());
          }
        }
      }
    }
    final list = set.toList();
    list.sort((a, b) => norm(a).compareTo(norm(b)));
    return list;
  }

  static List<String> coletarCores(List<Map<String, dynamic>> produtos) {
    final set = <String>{};
    for (final p in produtos) {
      final v = p['variacoes'];
      if (v is Map) {
        for (final e in v.values) {
          if (e is Map) {
            for (final ck in e.keys) {
              final s = ck.toString().trim();
              if (s.isEmpty) continue;
              set.add(s);
            }
          }
        }
      }
      final epc = p['estoquePorCor'];
      if (epc is Map) {
        for (final ck in epc.keys) {
          if (CatalogEstoqueHelper.parseQtd(epc[ck]) > 0) {
            set.add(ck.toString());
          }
        }
      }
    }
    final list = set.toList();
    list.sort((a, b) => norm(a).compareTo(norm(b)));
    return list;
  }

  /// Valores de personalização (extraValor) entre produtos já filtrados no contexto.
  static List<String> coletarExtras(List<Map<String, dynamic>> produtos) {
    return ProdutoVariacaoExtra.coletarExtrasGlobais(produtos);
  }
}
