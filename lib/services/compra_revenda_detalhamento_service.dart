// Detalhamento posterior de produtos em compras revenda_detalhar_depois.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../core/hive_box_names.dart';
import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';
import '../models/compra_fornecedor_item.dart';
import '../models/produto.dart';
import 'compra_fornecedor_firestore_service.dart';
import 'compra_fornecedor_hive_store.dart';
import 'compra_fornecedor_estorno_snapshot.dart';
import 'compra_fornecedor_item_estorno_service.dart';
import 'estoque_service.dart';

/// Marcador em [CompraFornecedorItem.observacaoItem] para auditoria.
const String kOrigemItemRevendaDetalharDepois = 'origem:compra_revenda_detalhar_depois';

/// Item removido do detalhamento (auditoria em observação, se mantido em histórico).
const String kOrigemItemExcluidoDetalhamento = 'origem:item_excluido_detalhamento';

class ResultadoDetalhamentoProduto {
  const ResultadoDetalhamentoProduto({
    required this.sucesso,
    this.mensagem = '',
    this.compraAtualizada,
  });

  final bool sucesso;
  final String mensagem;
  final CompraFornecedor? compraAtualizada;
}

abstract final class CompraRevendaDetalhamentoService {
  CompraRevendaDetalhamentoService._();

  static const double _toleranciaConferencia = 0.05;

  static Iterable<CompraFornecedor> listarPendentesDetalhamento(
    Box<CompraFornecedor> box,
    String lojaId,
  ) {
    final lid = lojaId.trim();
    return box.values.where(
      (c) =>
          c.lojaId.trim() == lid &&
          c.ehCompraRevendaDetalharDepois &&
          c.statusCompra == CompraFornecedorStatusCompra.confirmada &&
          CompraFornecedorStatusDetalhamento.pendente(
            c.statusDetalhamentoProdutos,
          ),
    );
  }

  static int contarPendentesDetalhamento(Box<CompraFornecedor> box, String lojaId) =>
      listarPendentesDetalhamento(box, lojaId).length;

  static double somarValorItensDetalhados(CompraFornecedor compra) {
    var t = 0.0;
    for (final it in compra.itensOuVazio) {
      t += it.subtotal;
    }
    return t;
  }

  static CompraFornecedor recalcularCamposDetalhamento(CompraFornecedor compra) {
    if (!compra.ehCompraRevendaDetalharDepois) return compra;

    final valorDet = somarValorItensDetalhados(compra);
    final totalRef = compra.valorCompraParaConferenciaDetalhamento;
    final diff = totalRef - valorDet;
    final qItens = compra.itensOuVazio.length;

    String st;
    if (qItens == 0) {
      st = CompraFornecedorStatusDetalhamento.aguardandoDetalhamento;
    } else if (compra.statusDetalhamentoProdutos ==
        CompraFornecedorStatusDetalhamento.conferido) {
      st = CompraFornecedorStatusDetalhamento.conferido;
    } else if (diff.abs() <= _toleranciaConferencia) {
      st = CompraFornecedorStatusDetalhamento.detalhado;
    } else {
      st = CompraFornecedorStatusDetalhamento.parcialmenteDetalhado;
    }

    return compra.copyWith(
      valorProdutosDetalhados: valorDet,
      diferencaDetalhamento: diff,
      quantidadeItensDetalhados: qItens,
      statusDetalhamentoProdutos: st,
      detalhamentoProdutosAt:
          qItens > 0 ? (compra.detalhamentoProdutosAt ?? DateTime.now()) : null,
      atualizadoEm: DateTime.now(),
    );
  }

  static CompraFornecedorItem _novoItem({
    required CompraFornecedor compra,
    required String produtoNome,
    required int quantidade,
    required double custoUnitario,
    String? productId,
    String? itemCompraId,
    String observacaoExtra = '',
    String tamanho = '',
    String cor = '',
  }) {
    final obs = <String>[
      kOrigemItemRevendaDetalharDepois,
      if (tamanho.trim().isNotEmpty) 'tam:${tamanho.trim()}',
      if (cor.trim().isNotEmpty) 'cor:${cor.trim()}',
      if (observacaoExtra.trim().isNotEmpty) observacaoExtra.trim(),
    ].join(' · ');
    return CompraFornecedorItem(
      produtoNome: produtoNome,
      quantidade: quantidade,
      custoUnitario: custoUnitario,
      productId: productId,
      itemCompraId: itemCompraId?.trim().isNotEmpty == true
          ? itemCompraId!.trim()
          : const Uuid().v4(),
      observacaoItem: obs,
      subtotalBase: quantidade * custoUnitario,
      custoUnitarioFinal: custoUnitario,
      subtotalFinal: quantidade * custoUnitario,
    );
  }

  /// Produto já cadastrado: soma estoque (devolução) e vincula item à compra.
  static Future<ResultadoDetalhamentoProduto> vincularProdutoExistente({
    required String lojaId,
    required CompraFornecedor compra,
    required Produto produto,
    required int quantidade,
    required double custoUnitario,
    String tamanho = '',
    String cor = '',
    String observacaoExtra = '',
  }) async {
    if (!compra.ehCompraRevendaDetalharDepois) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Compra não é do tipo revenda detalhar depois.',
      );
    }
    if (quantidade <= 0 || custoUnitario <= 0) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Informe quantidade e custo unitário válidos.',
      );
    }

    final item = await _entradaItemDetalhado(
      lojaId: lojaId,
      compra: compra,
      produto: produto,
      quantidade: quantidade,
      custoUnitario: custoUnitario,
      observacaoExtra: observacaoExtra,
      tamanho: tamanho,
      cor: cor,
    );
    if (item == null) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Falha ao aplicar entrada de estoque.',
      );
    }
    return _persistirItemNaCompra(lojaId, compra, item);
  }

  static Future<CompraFornecedorItem?> _entradaItemDetalhado({
    required String lojaId,
    required CompraFornecedor compra,
    required Produto produto,
    required int quantidade,
    required double custoUnitario,
    String? itemCompraId,
    String observacaoExtra = '',
    String tamanho = '',
    String cor = '',
    bool produtoNovoNaCompra = false,
  }) async {
    final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
    final snap = CompraFornecedorEstornoSnapshot.capturarAntesEntrada(
      produto,
      tamanho: tamanho,
      cor: cor,
    );
    final est = await EstoqueService.atualizarEstoque(
      produtosBox: prodBox,
      lojaId: lojaId,
      produtoId: produto.idFirebase.isNotEmpty ? produto.idFirebase : null,
      produtoNome: produto.nome,
      produtoSlug: produto.slug,
      tamanho: tamanho,
      cor: cor,
      quantidade: quantidade,
      operacao: 'entrada_compra',
    );
    if (!est.sucesso) return null;

    if (custoUnitario > 0 && est.produto != null) {
      est.produto!.custoReal = custoUnitario;
      await est.produto!.save();
    }

    var item = _novoItem(
      compra: compra,
      produtoNome: produto.nome,
      quantidade: quantidade,
      custoUnitario: custoUnitario,
      productId: produto.idFirebase.isNotEmpty ? produto.idFirebase : null,
      itemCompraId: itemCompraId,
      observacaoExtra: observacaoExtra,
      tamanho: tamanho,
      cor: cor,
    );
    return item.copyWith(
      itemCompraId: itemCompraId ?? item.itemCompraId,
      estoqueEntradaRegistrada: true,
      estoqueSnapshotOk: true,
      estoqueAnterior: snap.estoqueAnterior,
      custoAnterior: snap.custoAnterior,
      custoEntradaRegistrado: custoUnitario,
      tamanhoEntrada: tamanho.trim(),
      corEntrada: cor.trim(),
      produtoNovoNaCompra: produtoNovoNaCompra,
    );
  }

  /// Produto recém-criado no formulário (estoque já gravado no cadastro).
  static Future<ResultadoDetalhamentoProduto> vincularProdutoNovoJaSalvo({
    required String lojaId,
    required CompraFornecedor compra,
    required Produto produto,
    double? custoUnitarioOverride,
    String observacaoExtra = '',
  }) async {
    if (!compra.ehCompraRevendaDetalharDepois) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Compra não é do tipo revenda detalhar depois.',
      );
    }
    final qtd = produto.quantidade;
    if (qtd <= 0) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Produto sem quantidade para vincular.',
      );
    }
    final custo = (custoUnitarioOverride ?? produto.custoReal).clamp(0.0, 1e15);
    if (custo <= 0) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Informe o custo unitário do produto.',
      );
    }

    final item = _novoItem(
      compra: compra,
      produtoNome: produto.nome,
      quantidade: qtd,
      custoUnitario: custo,
      productId: produto.idFirebase.isNotEmpty ? produto.idFirebase : null,
      observacaoExtra: observacaoExtra,
    ).copyWith(
      estoqueEntradaRegistrada: true,
      estoqueSnapshotOk: true,
      estoqueAnterior: 0,
      custoAnterior: 0,
      custoEntradaRegistrado: custo,
      produtoNovoNaCompra: true,
    );

    return _persistirItemNaCompra(lojaId, compra, item);
  }

  /// Remove item do detalhamento (estorna estoque se já havia entrada).
  static Future<ResultadoDetalhamentoProduto> excluirItemDetalhadoCompra({
    required String lojaId,
    required CompraFornecedor compra,
    required String itemCompraId,
  }) async {
    if (!compra.ehCompraRevendaDetalharDepois) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Compra não é do tipo revenda detalhar depois.',
      );
    }
    final id = itemCompraId.trim();
    if (id.isEmpty) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Item inválido.',
      );
    }

    final itens = List<CompraFornecedorItem>.from(compra.itensOuVazio);
    final idx = itens.indexWhere((x) => x.itemCompraId.trim() == id);
    if (idx < 0) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Item não encontrado na compra.',
      );
    }

    final item = itens[idx];
    if (CompraFornecedorItemEstornoService.itemExigeEstornoSeguro(item)) {
      final est = await CompraFornecedorItemEstornoService.estornarEntradaItemCompra(
        lojaId: lojaId,
        item: item,
      );
      if (!est.sucesso) {
        return ResultadoDetalhamentoProduto(
          sucesso: false,
          mensagem: est.mensagem,
        );
      }
    } else if (item.produtoNovoNaCompra) {
      final prodBox =
          await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));
      final produto = CompraFornecedorItemEstornoService.resolverProduto(
        prodBox,
        item,
      );
      if (produto != null) {
        produto.ativoNoRascunho = false;
        await produto.save();
      }
    }

    itens.removeAt(idx);
    return _persistirCompraComItens(lojaId, compra, itens);
  }

  /// Edita item já detalhado: estorna entrada antiga e aplica nova (mesmo [itemCompraId]).
  static Future<ResultadoDetalhamentoProduto> editarItemDetalhadoCompra({
    required String lojaId,
    required CompraFornecedor compra,
    required String itemCompraId,
    required Produto produto,
    required int quantidade,
    required double custoUnitario,
    String tamanho = '',
    String cor = '',
    String observacaoExtra = '',
  }) async {
    if (!compra.ehCompraRevendaDetalharDepois) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Compra não é do tipo revenda detalhar depois.',
      );
    }
    if (quantidade <= 0 || custoUnitario <= 0) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Informe quantidade e custo unitário válidos.',
      );
    }

    final id = itemCompraId.trim();
    final itens = List<CompraFornecedorItem>.from(compra.itensOuVazio);
    final idx = itens.indexWhere((x) => x.itemCompraId.trim() == id);
    if (idx < 0) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Item não encontrado na compra.',
      );
    }

    final antigo = itens[idx];
    if (CompraFornecedorItemEstornoService.itemExigeEstornoSeguro(antigo)) {
      final est = await CompraFornecedorItemEstornoService.estornarEntradaItemCompra(
        lojaId: lojaId,
        item: antigo,
      );
      if (!est.sucesso) {
        return ResultadoDetalhamentoProduto(
          sucesso: false,
          mensagem: est.mensagem,
        );
      }
    }

    final novo = await _entradaItemDetalhado(
      lojaId: lojaId,
      compra: compra,
      produto: produto,
      quantidade: quantidade,
      custoUnitario: custoUnitario,
      itemCompraId: id,
      observacaoExtra: observacaoExtra,
      tamanho: tamanho,
      cor: cor,
      produtoNovoNaCompra: antigo.produtoNovoNaCompra,
    );
    if (novo == null) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Falha ao aplicar nova entrada de estoque.',
      );
    }

    itens[idx] = novo;
    return _persistirCompraComItens(lojaId, compra, itens);
  }

  static Future<ResultadoDetalhamentoProduto> marcarConferido({
    required String lojaId,
    required CompraFornecedor compra,
    String observacao = '',
  }) async {
    final box = await CompraFornecedorHiveStore.openBox(lojaId);
    if (box == null) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Armazenamento indisponível.',
      );
    }
    final now = DateTime.now();
    var atualizada = recalcularCamposDetalhamento(compra).copyWith(
      statusDetalhamentoProdutos: CompraFornecedorStatusDetalhamento.conferido,
      detalhamentoProdutosConferidoAt: now,
      observacaoDetalhamento: observacao.trim().isNotEmpty
          ? observacao.trim()
          : compra.observacaoDetalhamento,
      estoqueIntegrado: true,
      atualizadoEm: now,
    );
    await box.put(atualizada.id, atualizada);
    await _syncFirestore(atualizada);
    return ResultadoDetalhamentoProduto(
      sucesso: true,
      compraAtualizada: atualizada,
    );
  }

  static Future<ResultadoDetalhamentoProduto> _persistirItemNaCompra(
    String lojaId,
    CompraFornecedor compra,
    CompraFornecedorItem item,
  ) async {
    final itens = List<CompraFornecedorItem>.from(compra.itensOuVazio)..add(item);
    final r = await _persistirCompraComItens(lojaId, compra, itens);
    if (r.sucesso) {
      debugPrint(
        '[REVENDA-DET] Item vinculado compra=${r.compraAtualizada?.id} '
        'produto=${item.produtoNome} qtd=${item.quantidade}',
      );
    }
    return r;
  }

  static Future<ResultadoDetalhamentoProduto> _persistirCompraComItens(
    String lojaId,
    CompraFornecedor compra,
    List<CompraFornecedorItem> itens,
  ) async {
    final box = await CompraFornecedorHiveStore.openBox(lojaId);
    if (box == null) {
      return const ResultadoDetalhamentoProduto(
        sucesso: false,
        mensagem: 'Armazenamento da compra indisponível.',
      );
    }

    var atualizada = compra.copyWith(itens: itens);
    atualizada = recalcularCamposDetalhamento(atualizada);

    await box.put(atualizada.id, atualizada);
    await _syncFirestore(atualizada);

    return ResultadoDetalhamentoProduto(
      sucesso: true,
      compraAtualizada: atualizada,
    );
  }

  static Future<void> _syncFirestore(CompraFornecedor c) async {
    try {
      await CompraFornecedorFirestoreService.upsertCompra(c);
    } catch (e) {
      debugPrint('[REVENDA-DET] Sync Firestore falhou (type=${e.runtimeType})');
    }
  }
}
