// Estorno seguro de entrada de um item de compra (edição/exclusão revenda).

import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../models/compra_fornecedor_item.dart';
import '../models/produto.dart';
import 'compra_fornecedor_estorno_snapshot.dart';
import 'estoque_service.dart';

class ResultadoEstornoItemCompra {
  const ResultadoEstornoItemCompra({
    required this.sucesso,
    this.mensagem = '',
    this.custoNaoRestaurado = false,
  });

  final bool sucesso;
  final String mensagem;
  final bool custoNaoRestaurado;

  factory ResultadoEstornoItemCompra.erro(String msg) =>
      ResultadoEstornoItemCompra(sucesso: false, mensagem: msg);
}

abstract final class CompraFornecedorItemEstornoService {
  CompraFornecedorItemEstornoService._();

  static const String msgEstoqueInsuficienteEdicao =
      'Este produto já teve movimentação depois da entrada. '
      'Não é possível editar/excluir automaticamente sem deixar o estoque inconsistente.';

  static ({String tam, String cor}) tamCorDoItem(CompraFornecedorItem item) {
    var tam = item.tamanhoEntrada.trim();
    var cor = item.corEntrada.trim();
    if (tam.isEmpty && cor.isEmpty) {
      final parsed =
          CompraFornecedorEstornoSnapshot.parseTamCorObservacao(item.observacaoItem);
      tam = parsed.tam;
      cor = parsed.cor;
    }
    return (tam: tam, cor: cor);
  }

  static Produto? resolverProduto(Box<Produto> prodBox, CompraFornecedorItem item) {
    final pid = item.productId?.trim() ?? '';
    if (pid.isNotEmpty) {
      for (final p in prodBox.values) {
        if (p.idFirebase.trim() == pid) return p;
      }
    }
    final nomeAlvo = item.produtoNome.trim();
    for (final p in prodBox.values) {
      if (p.nome.trim() == nomeAlvo) return p;
    }
    return null;
  }

  /// Item com entrada já registrada exige snapshot válido para estornar.
  static bool itemExigeEstornoSeguro(CompraFornecedorItem item) =>
      item.estoqueEntradaRegistrada;

  static Future<ResultadoEstornoItemCompra?> validarPodeEstornarItemCompra({
    required String lojaId,
    required CompraFornecedorItem item,
    Box<Produto>? produtosBox,
  }) async {
    if (!itemExigeEstornoSeguro(item)) return null;
    if (!item.estoqueSnapshotOk) {
      return ResultadoEstornoItemCompra.erro(
        'Item sem dados de estorno. Ajuste manualmente ou cancele a compra.',
      );
    }

    final prodBox =
        produtosBox ?? await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    final tamCor = tamCorDoItem(item);
    final produto = resolverProduto(prodBox, item);
    if (produto == null) {
      return ResultadoEstornoItemCompra.erro(
        'Produto não encontrado: ${item.produtoNome}',
      );
    }
    if (!CompraFornecedorEstornoSnapshot.estoqueSuficienteParaEstorno(
      produto,
      item,
      tamanho: tamCor.tam,
      cor: tamCor.cor,
    )) {
      return ResultadoEstornoItemCompra.erro(msgEstoqueInsuficienteEdicao);
    }
    return null;
  }

  /// Estorna quantidade da entrada e restaura custo quando seguro.
  static Future<ResultadoEstornoItemCompra> estornarEntradaItemCompra({
    required String lojaId,
    required CompraFornecedorItem item,
    Box<Produto>? produtosBox,
  }) async {
    final pre = await validarPodeEstornarItemCompra(
      lojaId: lojaId,
      item: item,
      produtosBox: produtosBox,
    );
    if (pre != null) return pre;

    if (!itemExigeEstornoSeguro(item)) {
      return const ResultadoEstornoItemCompra(sucesso: true);
    }

    final prodBox =
        produtosBox ?? await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    final tamCor = tamCorDoItem(item);
    final produto = resolverProduto(prodBox, item)!;

    final est = await EstoqueService.atualizarEstoque(
      produtosBox: prodBox,
      lojaId: lojaId,
      produtoId: produto.idFirebase.isNotEmpty ? produto.idFirebase : null,
      produtoNome: produto.nome,
      produtoSlug: produto.slug,
      tamanho: tamCor.tam,
      cor: tamCor.cor,
      quantidade: item.quantidade,
      operacao: EstoqueOperacaoCompra.estornoItemCompra,
    );
    if (!est.sucesso) {
      return ResultadoEstornoItemCompra.erro(est.mensagem);
    }

    var custoNaoRestaurado = false;
    final produtoPos = resolverProduto(prodBox, item) ?? produto;
    if (CompraFornecedorEstornoSnapshot.podeRestaurarCusto(item, produtoPos)) {
      produtoPos.custoReal = item.custoAnterior;
      await produtoPos.save();
    } else {
      custoNaoRestaurado = true;
    }

    if (item.produtoNovoNaCompra) {
      produtoPos.ativoNoRascunho = false;
      await produtoPos.save();
    }

    return ResultadoEstornoItemCompra(
      sucesso: true,
      custoNaoRestaurado: custoNaoRestaurado,
    );
  }
}
