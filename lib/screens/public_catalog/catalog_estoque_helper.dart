// lib/screens/public_catalog/catalog_estoque_helper.dart
// Leitura centralizada de estoque no catálogo público (Firestore → UI/carrinho).
// Retrocompatível: não altera nomes de campos do banco.

import 'dart:math' as math;

import '../../core/produto_variacao_extra.dart';
import '../../core/produto_variacao_normalizer.dart';
import '../../core/safe_cast.dart';

/// Helpers de estoque para catálogo público (produtos processados ou raw Firestore).
class CatalogEstoqueHelper {
  CatalogEstoqueHelper._();

  /// Documento vindo do Firestore (`produtos` LIVE): deve aparecer na vitrine web.
  /// Qualquer um dos campos [publicadoNoCatalogo], [publicarNoCatalogo], [publicar]
  /// explicitamente `false` esconde o item (botão Publicar desmarcado / sync).
  /// Ausente ou `true`: considera publicado (compatível com documentos antigos).
  static bool catalogoWebDocPublicado(Map<String, dynamic> m) {
    final v = m['publicadoNoCatalogo'] ?? m['publicarNoCatalogo'] ?? m['publicar'];
    return v != false;
  }

  static int parseQtd(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  /// Quantidade no carrinho: null → 1; aceita int, double, num, String.
  static int parseCartItemQuantidade(dynamic v) {
    if (v == null) return 1;
    if (v is int) return v;
    if (v is num) return v.toInt();
    final p = int.tryParse(v.toString().trim());
    return p ?? 1;
  }

  /// Fallback numérico: prioridade explícita; [quantidade] só se nenhum campo “de estoque” existir.
  static int readFallbackNumericStock(Map<String, dynamic> m) {
    const keys = <String>[
      'estoque_atual',
      'estoque',
      'estoqueAtual',
      'qtdEstoque',
      'qtd_estoque',
      'estoque_disponivel',
    ];
    for (final key in keys) {
      if (!m.containsKey(key)) continue;
      final raw = m[key];
      if (raw == null) continue;
      return parseQtd(raw);
    }
    return parseQtd(m['quantidade']);
  }

  static int _sumVariacoesTotal(Map<String, dynamic>? variacoes) {
    if (variacoes == null || variacoes.isEmpty) return 0;
    var s = 0;
    variacoes.forEach((_, cores) {
      if (cores is Map) {
        for (final v in cores.values) {
          s += ProdutoVariacaoExtra.somarCelula(v);
        }
      }
    });
    return s;
  }

  /// Cores que já aparecem em algum tamanho dentro de [variacoes].
  static Set<String> _coresPresentesEmVariacoes(Map<String, dynamic> variacoes) {
    final set = <String>{};
    variacoes.forEach((t, cores) {
      if (cores is Map) {
        for (final k in cores.keys) {
          set.add(k.toString());
        }
      }
    });
    return set;
  }

  static dynamic _rawCellNoMapa(Map<dynamic, dynamic> mapa, String cor) {
    if (cor.isEmpty) return null;
    if (mapa.containsKey(cor)) return mapa[cor];
    final lower = cor.toLowerCase();
    for (final e in mapa.entries) {
      if (e.key.toString().toLowerCase() == lower) return e.value;
    }
    return null;
  }

  static int _qtdCorNoMapa(Map<dynamic, dynamic> mapa, String cor) {
    return ProdutoVariacaoExtra.somarCelula(_rawCellNoMapa(mapa, cor));
  }

  static int _sumMapValuesNested(Map<dynamic, dynamic>? map) {
    if (map == null || map.isEmpty) return 0;
    var s = 0;
    for (final v in map.values) {
      s += ProdutoVariacaoExtra.somarCelula(v);
    }
    return s;
  }

  /// Resultado do processamento de estoque a partir do mapa Firestore (ou já normalizado).
  static ({
    int quantidadeTotal,
    Map<String, int>? estoquePorTamanho,
    Map<String, int>? estoquePorCor,
    Map<String, dynamic>? variacoes,
    bool incluirNoCatalogo,
  }) processStockFromFirestoreMap(
    Map<String, dynamic> m, {
    required bool isCombo,
  }) {
    final mNorm = Map<String, dynamic>.from(m);
    ProdutoVariacaoNormalizer.applyToCatalogProductMap(mNorm);
    m = mNorm;

    final estoqueBase = readFallbackNumericStock(m);

    Map<String, int>? estoquePorTamanho;
    final estoqueTamRaw = m['estoquePorTamanho'];
    var somaTam = 0;
    if (estoqueTamRaw is Map && estoqueTamRaw.isNotEmpty) {
      estoquePorTamanho = {};
      estoqueTamRaw.forEach((key, value) {
        final q = parseQtd(value);
        if (q > 0) {
          estoquePorTamanho![key.toString()] = q;
          somaTam += q;
        }
      });
      if (estoquePorTamanho.isEmpty) estoquePorTamanho = null;
    }

    Map<String, dynamic>? variacoes;
    final variacoesRaw = m['variacoes'];
    if (variacoesRaw is Map && variacoesRaw.isNotEmpty) {
      variacoes = asMapDeep(variacoesRaw);
    }

    Map<String, int>? mapCorRoot;
    final estoqueCorRaw = m['estoquePorCor'];
    if (estoqueCorRaw is Map && estoqueCorRaw.isNotEmpty) {
      mapCorRoot = {};
      estoqueCorRaw.forEach((key, value) {
        final q = parseQtd(value);
        if (q > 0) mapCorRoot![key.toString()] = q;
      });
      if (mapCorRoot.isEmpty) mapCorRoot = null;
    }

    final somaVar = _sumVariacoesTotal(variacoes);
    var extraRootCor = 0;
    if (mapCorRoot != null && variacoes != null && variacoes.isNotEmpty) {
      final inVar = _coresPresentesEmVariacoes(variacoes);
      for (final e in mapCorRoot.entries) {
        if (!inVar.contains(e.key)) {
          extraRootCor += e.value;
        }
      }
    }

    final mapCorMerged = <String, int>{};
    if (mapCorRoot != null) {
      mapCorMerged.addAll(mapCorRoot);
    }
    if (variacoes != null &&
        variacoes['sem-tamanho'] is Map &&
        (variacoes['sem-tamanho'] as Map).isNotEmpty) {
      final sem = variacoes['sem-tamanho'] as Map;
      sem.forEach((key, value) {
        final q = ProdutoVariacaoExtra.somarCelula(value);
        if (q > 0) mapCorMerged[key.toString()] = q;
      });
    }

    Map<String, int>? estoquePorCorOut =
        mapCorMerged.isEmpty ? null : Map<String, int>.from(mapCorMerged);

    var somaCorOnly = mapCorRoot == null ? 0 : mapCorRoot.values.fold(0, (a, b) => a + b);

    int quantidadeTotal;
    if (isCombo) {
      if (somaVar > 0) {
        quantidadeTotal = somaVar + extraRootCor;
      } else if (somaTam > 0) {
        quantidadeTotal = somaTam;
      } else if (somaCorOnly > 0 && variacoes == null) {
        quantidadeTotal = somaCorOnly;
      } else if (estoquePorCorOut != null && variacoes != null && somaVar == 0) {
        quantidadeTotal = estoquePorCorOut.values.fold(0, (a, b) => a + b) + extraRootCor;
      } else {
        // Sem estoque real: não inventar quantidade (evita combo “fantasma” no catálogo).
        quantidadeTotal = estoqueBase > 0 ? estoqueBase : 0;
      }
    } else {
      if (somaVar > 0) {
        quantidadeTotal = somaVar + extraRootCor;
      } else if (somaTam > 0) {
        quantidadeTotal = somaTam;
      } else if (mapCorRoot != null && somaCorOnly > 0) {
        quantidadeTotal = somaCorOnly;
      } else {
        quantidadeTotal = estoqueBase;
      }
    }

    final temAlgum = somaVar > 0 ||
        extraRootCor > 0 ||
        somaTam > 0 ||
        somaCorOnly > 0 ||
        estoqueBase > 0;
    // Combo também precisa de estoque > 0 em alguma forma (não listar kit zerado).
    final incluirNoCatalogo = temAlgum;

    return (
      quantidadeTotal: quantidadeTotal,
      estoquePorTamanho: estoquePorTamanho,
      estoquePorCor: estoquePorCorOut,
      variacoes: variacoes,
      incluirNoCatalogo: incluirNoCatalogo,
    );
  }

  /// Há pelo menos uma variação (ou total) com estoque > 0?
  static bool temAlgumaVariacaoComEstoquePositivo(Map<String, dynamic> p) {
    final v = p['variacoes'];
    if (v is Map) {
      for (final cores in v.values) {
        if (cores is Map) {
          for (final q in cores.values) {
            if (ProdutoVariacaoExtra.somarCelula(q) > 0) return true;
          }
        }
      }
    }
    final et = p['estoquePorTamanho'];
    if (et is Map) {
      for (final q in et.values) {
        if (parseQtd(q) > 0) return true;
      }
    }
    final ec = p['estoquePorCor'];
    if (ec is Map) {
      for (final q in ec.values) {
        if (parseQtd(q) > 0) return true;
      }
    }
    return parseQtd(p['quantidade']) > 0;
  }

  static bool _ehComboMap(Map<String, dynamic> p) {
    if (p['tipoProduto']?.toString() == 'combo') return true;
    final ic = p['itensCombo'];
    return ic is List && ic.isNotEmpty;
  }

  /// Filtro “apenas em estoque”: combo sempre passa; demais exigem estoque real em alguma variação.
  static bool produtoPassaFiltroApenasEmEstoque(Map<String, dynamic> p) {
    if (_ehComboMap(p)) return true;
    return temAlgumaVariacaoComEstoquePositivo(p);
  }

  /// Estoque disponível para a variação (tamanho/cor) selecionada.
  static int estoqueDisponivelVariacao(
    Map<String, dynamic> p,
    String tamanho,
    String cor, [
    String variacaoExtra = '',
  ]) {
    final tam = tamanho.trim();
    final c = cor.trim();
    final ex = variacaoExtra.trim();
    final variacoes = p['variacoes'];
    if (variacoes is Map && variacoes.isNotEmpty) {
      if (tam.isNotEmpty && variacoes[tam] is Map) {
        final mapa = variacoes[tam] as Map;
        if (c.isNotEmpty) {
          final cell = _rawCellNoMapa(mapa, c);
          if (ProdutoVariacaoExtra.celulaTemExtrasNaoVazios(cell)) {
            if (ex.isEmpty) return 0;
            final q = ProdutoVariacaoExtra.quantidadeNaCelula(cell, ex);
            if (q > 0) return q;
          } else {
            final q = _qtdCorNoMapa(mapa, c);
            if (q > 0) return q;
          }
        }
        return _sumMapValuesNested(mapa);
      }
      if ((tam.isEmpty || tam == 'sem-tamanho') &&
          variacoes['sem-tamanho'] is Map) {
        final mapa = variacoes['sem-tamanho'] as Map;
        if (c.isNotEmpty) {
          final cell = _rawCellNoMapa(mapa, c);
          if (ProdutoVariacaoExtra.celulaTemExtrasNaoVazios(cell)) {
            if (ex.isEmpty) return 0;
            final q = ProdutoVariacaoExtra.quantidadeNaCelula(cell, ex);
            if (q > 0) return q;
          } else {
            final q = _qtdCorNoMapa(mapa, c);
            if (q > 0) return q;
          }
        }
        return _sumMapValuesNested(mapa);
      }
    }
    final ept = p['estoquePorTamanho'];
    final epc = p['estoquePorCor'];
    if (ept is Map && tam.isNotEmpty) {
      final qt = parseQtd(ept[tam]);
      if (qt > 0) {
        if (epc is Map && c.isNotEmpty) {
          final qc = _qtdCorNoMapa(epc, c);
          if (qc > 0) return qc < qt ? qc : qt;
        }
        return qt;
      }
    }
    if (epc is Map && c.isNotEmpty) {
      final qc = _qtdCorNoMapa(epc, c);
      if (qc > 0) return qc;
    }
    return parseQtd(p['quantidade']);
  }

  /// Para uma receita **por kit** já resolvida (ex.: seleção do combo configurável),
  /// estima quantos kits completos cabem usando estoque agregado por SKU (sem tam/cor/extra).
  /// Retorna `0` se linha inválida, `productId` vazio ou produto ausente no catálogo.
  static int maxKitsMontaveisParaReceitaCatalogo({
    required List<Map<String, dynamic>> catalogProducts,
    required List<Map<String, dynamic>> linhasPorKit,
  }) {
    if (linhasPorKit.isEmpty) return 0;
    int? cap;
    for (final linha in linhasPorKit) {
      final pid = (linha['productId'] ?? linha['id'] ?? '').toString().trim();
      final qtd = linha['quantidade'] is num
          ? (linha['quantidade'] as num).toInt()
          : int.tryParse('${linha['quantidade']}') ?? 0;
      if (pid.isEmpty || qtd <= 0) return 0;
      final p = findProductInList(catalogProducts, pid);
      if (p == null) return 0;
      final tam = (linha['tamanho'] ?? '').toString().trim();
      final cor = (linha['cor'] ?? '').toString().trim();
      final ex = (linha['extraValor'] ?? linha['variacaoExtra'] ?? '')
          .toString()
          .trim();
      final avail = estoqueDisponivelVariacao(p, tam, cor, ex);
      final kits = avail ~/ qtd;
      final prev = cap;
      cap = prev == null ? kits : (kits < prev ? kits : prev);
    }
    return cap ?? 0;
  }

  /// Identidade de linha do carrinho (merge e validação).
  static String cartLineIdentity(Map<String, dynamic> item) {
    final id = '${item['id'] ?? item['produtosId'] ?? ''}';
    final tam = (item['tamanho'] ?? '').toString().trim().toLowerCase();
    final cr = (item['cor'] ?? '').toString().trim().toLowerCase();
    final ex = (item['extraValor'] ?? item['variacaoExtra'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final combo = item['itensComboComSelecao'];
    if (combo is List && combo.isNotEmpty) {
      final buf = StringBuffer(id);
      buf.write('|combo');
      for (final e in combo) {
        if (e is Map) {
          final ex = (e['extraValor'] ?? e['variacaoExtra'] ?? '')
              .toString()
              .trim();
          buf.write(
            '|${e['productId'] ?? e['id'] ?? ''}|${e['tamanho']}|${e['cor']}|$ex|${e['quantidade']}',
          );
        }
      }
      return buf.toString();
    }
    return '$id|$tam|$cr|$ex';
  }

  /// Teto de unidades para a linha [index] (estoque da variação menos outras
  /// linhas com a mesma [cartLineIdentity]). Espelha o carrinho web.
  static int maxOrderableForCartLine({
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> catalogProducts,
    required int index,
  }) {
    if (index < 0 || index >= items.length) return 0;
    final item = items[index];
    final comboRaw = item['itensComboComSelecao'];
    if (comboRaw is List && comboRaw.isNotEmpty) {
      return 999999;
    }
    final id = '${item['id'] ?? item['produtosId'] ?? ''}';
    if (id.isEmpty) return 999999;
    final p = findProductInList(catalogProducts, id);
    if (p == null) return 999999;
    final avail = estoqueDisponivelVariacao(
      p,
      (item['tamanho'] ?? '').toString().trim(),
      (item['cor'] ?? '').toString().trim(),
      (item['extraValor'] ?? item['variacaoExtra'] ?? '').toString().trim(),
    );
    final lineKey = cartLineIdentity(item);
    var other = 0;
    for (var i = 0; i < items.length; i++) {
      if (i == index) continue;
      if (cartLineIdentity(items[i]) == lineKey) {
        other += parseCartItemQuantidade(items[i]['quantidade']);
      }
    }
    return math.max(0, avail - other);
  }

  static Map<String, dynamic>? findProductInList(
    List<Map<String, dynamic>> lista,
    String productId,
  ) {
    final key = productId.trim();
    if (key.isEmpty) return null;
    for (final p in lista) {
      final id = '${p['id'] ?? ''}'.trim();
      if (id.isNotEmpty && id == key) return p;
    }
    for (final p in lista) {
      final pid = '${p['produtosId'] ?? ''}'.trim();
      if (pid.isNotEmpty && pid == key) return p;
    }
    for (final p in lista) {
      final slug = '${p['slug'] ?? ''}'.trim();
      if (slug.isNotEmpty && slug == key) return p;
    }
    return null;
  }
}
