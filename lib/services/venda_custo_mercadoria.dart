// Custo de mercadoria (custo real de estoque) para vendas — separado de taxas operacionais.
//
// Regra: combo com receita expandida em filhos → custo só dos componentes baixados;
// linha do kit (pai) não entra na soma para não duplicar com os filhos.

import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../models/produto.dart';
import '../models/venda_item.dart';
import 'venda_combo_estoque_expansion.dart';

class VendaCustoMercadoria {
  VendaCustoMercadoria._();

  /// Soma [Produto.custoReal × VendaItem.quantidade] apenas nas linhas em que
  /// [linhaContaCustoMercadoria] é true (ex.: exclui cabeçalho de combo quando há filhos).
  static double somarCustoReal({
    required List<VendaItem> itens,
    required List<Produto> produtos,
    required List<bool> linhaContaCustoMercadoria,
  }) {
    assert(itens.length == produtos.length);
    assert(itens.length == linhaContaCustoMercadoria.length);
    var total = 0.0;
    for (var i = 0; i < itens.length; i++) {
      if (!linhaContaCustoMercadoria[i]) continue;
      total += produtos[i].custoReal * itens[i].quantidade;
    }
    return total;
  }

  /// Unidades físicas de mercadoria (para proxy legado embalagem R$/un na venda), alinhadas ao custo.
  static int unidadesMercadoria({
    required List<VendaItem> itens,
    required List<bool> linhaContaCustoMercadoria,
  }) {
    assert(itens.length == linhaContaCustoMercadoria.length);
    var u = 0;
    for (var i = 0; i < itens.length; i++) {
      if (!linhaContaCustoMercadoria[i]) continue;
      u += itens[i].quantidade;
    }
    return u;
  }

  /// Taxa legado gravada na venda (embalagem/un + % sobre custo de mercadoria) — não mistura MEI/cartão.
  static double taxasLegadoVendaApk({
    required double custoMercadoria,
    required int unidadesMercadoria,
  }) {
    return (3.50 * unidadesMercadoria) + (0.15 * custoMercadoria);
  }

  /// Catálogo: mesmo pipeline da baixa (mapas → VendaItem → expandirCombos).
  /// Se nada for resolvível ou custo for 0 com itens presentes, usa fallback explícito (heurística).
  static double custoMercadoriaDesdeItensCatalogo({
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
    required String lojaId,
    required double subtotalParaFallbackHeuristica,
  }) {
    if (items.isEmpty) {
      return 0.0;
    }
    try {
      final (vendaItens, comboPorIndice) =
          VendaComboEstoqueExpansion.carrinhoMapsParaVendaItensComComboSelecao(items);
      if (vendaItens.isEmpty) {
        logW(
          '[CUSTO_MERCADORIA] Carrinho vazio após mapeamento — fallback 50% subtotal '
          '(loja=$lojaId, subtotal=${subtotalParaFallbackHeuristica.toStringAsFixed(2)})',
          tag: 'CUSTO_FALLBACK',
        );
        return subtotalParaFallbackHeuristica * 0.5;
      }

      final (itensExp, prods, flags) = VendaComboEstoqueExpansion.expandirCombos(
        itens: vendaItens,
        produtosBox: produtosBox,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: comboPorIndice,
      );

      final custo = somarCustoReal(
        itens: itensExp,
        produtos: prods,
        linhaContaCustoMercadoria: flags,
      );

      if (custo <= 0 && subtotalParaFallbackHeuristica > 0) {
        logW(
          '[CUSTO_MERCADORIA] Custo resolvido zero com itens no carrinho — fallback 50% subtotal '
          '(loja=$lojaId, subtotal=${subtotalParaFallbackHeuristica.toStringAsFixed(2)})',
          tag: 'CUSTO_FALLBACK',
        );
        return subtotalParaFallbackHeuristica * 0.5;
      }

      return custo;
    } catch (e, st) {
      logW(
        '[CUSTO_MERCADORIA] Erro ao resolver custo real — fallback 50% subtotal '
        '(loja=$lojaId, type=${e.runtimeType}): $e',
        tag: 'CUSTO_FALLBACK',
      );
      logD('$st', tag: 'CUSTO_FALLBACK');
      return subtotalParaFallbackHeuristica * 0.5;
    }
  }

  /// Unidades para taxa legado no catálogo (alinhadas às linhas que entram no custo).
  static int unidadesMercadoriaDesdeItensCatalogo({
    required List<Map<String, dynamic>> items,
    required Box<Produto> produtosBox,
    required String lojaId,
  }) {
    if (items.isEmpty) return 0;
    try {
      final (vendaItens, comboPorIndice) =
          VendaComboEstoqueExpansion.carrinhoMapsParaVendaItensComComboSelecao(items);
      if (vendaItens.isEmpty) return 0;

      final (itensExp, _, flags) = VendaComboEstoqueExpansion.expandirCombos(
        itens: vendaItens,
        produtosBox: produtosBox,
        lojaId: lojaId,
        itensComboSelecaoPorIndice: comboPorIndice,
      );

      return unidadesMercadoria(itens: itensExp, linhaContaCustoMercadoria: flags);
    } catch (_) {
      return items.fold<int>(
        0,
        (s, m) =>
            s + ((m['quantidade'] as int?) ?? (m['qty'] as int?) ?? 1),
      );
    }
  }
}
