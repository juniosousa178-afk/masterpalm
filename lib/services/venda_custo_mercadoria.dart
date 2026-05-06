// Custo de mercadoria (custo real de estoque) para vendas — separado de taxas operacionais.
//
// Regra: combo com receita expandida em filhos → custo só dos componentes baixados;
// linha do kit (pai) não entra na soma para não duplicar com os filhos.

import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../core/venda_origem_custo.dart';
import '../models/produto.dart';
import '../models/venda.dart';
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
      final custoUnit = itens[i].custoUnitario ?? produtos[i].custoReal;
      total += custoUnit * itens[i].quantidade;
    }
    return total;
  }

  /// Preenche [VendaItem.origemCustoItem] sem alterar valores numéricos (usa o mesmo critério
  /// `custoUnitario ?? produto.custoReal` da soma: linha com custo explícito antes do resolver → item).
  static void aplicarRastreioOrigemAposSomarCustoReal({
    required List<VendaItem> itens,
    required List<Produto> produtos,
    required List<bool> linhaContaCustoMercadoria,
    required List<bool> tinhaCustoUnitarioExplicitoAntesDoResolver,
  }) {
    assert(itens.length == produtos.length);
    assert(itens.length == linhaContaCustoMercadoria.length);
    assert(itens.length == tinhaCustoUnitarioExplicitoAntesDoResolver.length);
    for (var i = 0; i < itens.length; i++) {
      if (!linhaContaCustoMercadoria[i]) {
        itens[i].origemCustoItem = null;
        continue;
      }
      itens[i].origemCustoItem =
          tinhaCustoUnitarioExplicitoAntesDoResolver[i]
              ? VendaOrigemCusto.item
              : VendaOrigemCusto.produto;
    }
  }

  /// Agrega rastreio ao nível da venda a partir das linhas que entram no CMV.
  static String agregarOrigemCustoVenda({
    required double custoProdutos,
    required Iterable<String?> origensLinhasAtivas,
  }) {
    if (custoProdutos == 0) return VendaOrigemCusto.zeroIntencional;
    final set = origensLinhasAtivas
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    if (set.isEmpty) return VendaOrigemCusto.desconhecido;
    if (set.length == 1) return set.single;
    return VendaOrigemCusto.desconhecido;
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
    Venda? vendaParaRastreio,
    List<VendaItem>? linhasCatalogoVendaItens,
  }) {
    void marcarFallbackNoRastreio() {
      if (vendaParaRastreio != null) {
        vendaParaRastreio.origemCusto = VendaOrigemCusto.fallback;
      }
      if (linhasCatalogoVendaItens != null) {
        for (final it in linhasCatalogoVendaItens) {
          it.origemCustoItem = VendaOrigemCusto.fallback;
        }
      }
    }

    void marcarZeroIntencionalNoRastreio() {
      if (vendaParaRastreio != null) {
        vendaParaRastreio.origemCusto = VendaOrigemCusto.zeroIntencional;
      }
      if (linhasCatalogoVendaItens != null) {
        for (final it in linhasCatalogoVendaItens) {
          it.origemCustoItem = VendaOrigemCusto.zeroIntencional;
        }
      }
    }

    if (items.isEmpty) {
      marcarZeroIntencionalNoRastreio();
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
        marcarFallbackNoRastreio();
        return subtotalParaFallbackHeuristica * 0.5;
      }

      final snapshotLinhasCatalogo = linhasCatalogoVendaItens != null &&
              linhasCatalogoVendaItens.length == vendaItens.length
          ? List<bool>.from(
              linhasCatalogoVendaItens.map((e) => e.custoUnitario != null),
            )
          : List<bool>.from(vendaItens.map((e) => e.custoUnitario != null));

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
        marcarFallbackNoRastreio();
        return subtotalParaFallbackHeuristica * 0.5;
      }

      if (vendaParaRastreio != null && linhasCatalogoVendaItens != null) {
        if (custo == 0) {
          marcarZeroIntencionalNoRastreio();
        } else {
          for (var j = 0; j < linhasCatalogoVendaItens.length; j++) {
            final ex = j < snapshotLinhasCatalogo.length
                ? snapshotLinhasCatalogo[j]
                : false;
            linhasCatalogoVendaItens[j].origemCustoItem =
                ex ? VendaOrigemCusto.item : VendaOrigemCusto.produto;
          }
          final todasItem =
              snapshotLinhasCatalogo.every((x) => x) && snapshotLinhasCatalogo.isNotEmpty;
          final todasProduto = snapshotLinhasCatalogo.every((x) => !x) &&
              snapshotLinhasCatalogo.isNotEmpty;
          vendaParaRastreio.origemCusto = todasItem
              ? VendaOrigemCusto.item
              : todasProduto
                  ? VendaOrigemCusto.produto
                  : VendaOrigemCusto.desconhecido;
        }
      }

      return custo;
    } catch (e, st) {
      logW(
        '[CUSTO_MERCADORIA] Erro ao resolver custo real — fallback 50% subtotal '
        '(loja=$lojaId, type=${e.runtimeType}): $e',
        tag: 'CUSTO_FALLBACK',
      );
      logD('$st', tag: 'CUSTO_FALLBACK');
      marcarFallbackNoRastreio();
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
