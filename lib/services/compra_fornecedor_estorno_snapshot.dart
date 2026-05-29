// Snapshot de estoque/custo antes de entrada vinculada à compra (estorno seguro).

import '../models/compra_fornecedor_item.dart';
import '../models/produto.dart';

/// Operação semântica de estorno de compra (subtrai estoque, sem confundir com venda).
abstract final class EstoqueOperacaoCompra {
  EstoqueOperacaoCompra._();
  static const String estornoCompra = 'estorno_compra';
}

abstract final class CompraFornecedorEstornoSnapshot {
  CompraFornecedorEstornoSnapshot._();

  static const double toleranciaCusto = 0.02;

  static int lerQuantidadeEstoque(
    Produto p, {
    String tamanho = '',
    String cor = '',
    String variacaoExtra = '',
  }) {
    final tam = tamanho.trim();
    final corTrim = cor.trim();
    final extra = variacaoExtra.trim();
    if (p.usaVariacoes && (tam.isNotEmpty || corTrim.isNotEmpty)) {
      final tamKey = tam.isEmpty ? '' : tam;
      final corKey = corTrim.isEmpty ? 'sem-cor' : corTrim;
      return p.obterEstoqueVariacao(tamKey, corKey, extra);
    }
    if (p.estoquePorTamanho.isNotEmpty && tam.isNotEmpty) {
      return p.estoquePorTamanho[tam] ?? 0;
    }
    return p.quantidade;
  }

  /// Extrai tam/cor de `observacaoItem` (formato revenda: tam:X · cor:Y).
  static ({String tam, String cor}) parseTamCorObservacao(String obs) {
    var tam = '';
    var cor = '';
    for (final part in obs.split('·')) {
      final p = part.trim();
      if (p.startsWith('tam:')) {
        tam = p.substring(4).trim();
      } else if (p.startsWith('cor:')) {
        cor = p.substring(4).trim();
      }
    }
    return (tam: tam, cor: cor);
  }

  static ({int estoqueAnterior, double custoAnterior}) capturarAntesEntrada(
    Produto produto, {
    String tamanho = '',
    String cor = '',
  }) {
    return (
      estoqueAnterior: lerQuantidadeEstoque(
        produto,
        tamanho: tamanho,
        cor: cor,
      ),
      custoAnterior: produto.custoReal,
    );
  }

  static bool estoqueSuficienteParaEstorno(
    Produto produto,
    CompraFornecedorItem item, {
    String tamanho = '',
    String cor = '',
  }) {
    final atual = lerQuantidadeEstoque(produto, tamanho: tamanho, cor: cor);
    return atual >= item.quantidade;
  }

  /// Só restaura custo se o atual ainda reflete o custo da entrada desta compra.
  static bool podeRestaurarCusto(CompraFornecedorItem item, Produto produto) {
    final entrada = item.custoEntradaEfetivo;
    if (entrada <= 0) return item.produtoNovoNaCompra && produto.custoReal <= toleranciaCusto;
    return (produto.custoReal - entrada).abs() <= toleranciaCusto;
  }
}
