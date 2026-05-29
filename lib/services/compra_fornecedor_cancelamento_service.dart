// Cancelamento seguro de compra de fornecedor (estoque, CP, LF vinculado).



import 'package:flutter/foundation.dart';

import 'package:hive/hive.dart';



import '../core/compra_item_pipeline_constants.dart';

import '../core/hive_box_names.dart';

import '../models/compra_fornecedor.dart';

import '../models/compra_fornecedor_constants.dart';

import '../models/compra_fornecedor_item.dart';

import '../models/conta_pagar_constants.dart';

import '../models/produto.dart';

import 'compra_financeiro_integracao_service.dart';

import 'compra_fornecedor_estorno_snapshot.dart';

import 'compra_fornecedor_firestore_service.dart';

import 'compra_fornecedor_hive_store.dart';

import 'compra_item_pipeline_store.dart';

import 'compra_para_pipeline_service.dart';

import 'conta_pagar_financeiro_exclusao_service.dart';

import 'conta_pagar_hive_store.dart';

import 'conta_pagar_service.dart';

import 'estoque_service.dart';



class ResultadoCancelamentoCompra {

  const ResultadoCancelamentoCompra({

    required this.sucesso,

    this.mensagem = '',

    this.estoqueEstornado = false,

    this.parcelasCanceladas = 0,

    this.compraAtualizada,

    this.custosNaoRestaurados = const [],

  });



  final bool sucesso;

  final String mensagem;

  final bool estoqueEstornado;

  final int parcelasCanceladas;

  final CompraFornecedor? compraAtualizada;

  /// Produtos cujo custo não foi revertido (alteração posterior à entrada).

  final List<String> custosNaoRestaurados;



  factory ResultadoCancelamentoCompra.erro(String msg) =>

      ResultadoCancelamentoCompra(sucesso: false, mensagem: msg);

}



abstract final class CompraFornecedorCancelamentoService {

  CompraFornecedorCancelamentoService._();



  static const String _msgSemSnapshot =

      'Esta compra não possui dados suficientes para estorno automático. '

      'Faça ajuste manual de estoque ou revise a compra.';



  static const String _msgEstoqueInsuficiente =

      'Esta compra já teve produtos movimentados/vendidos depois da entrada. '

      'Não é possível estornar automaticamente sem deixar o estoque inconsistente.';



  /// UI: confirmação com aviso de estorno de estoque.

  static bool exigeAvisoEstornoNaConfirmacao(CompraFornecedor compra) {

    if (compra.ehCompraFinanceira) return false;

    return _itensComEntradaEstoque(compra).isNotEmpty;

  }



  static List<CompraFornecedorItem> _itensComEntradaEstoque(CompraFornecedor c) =>

      c.itensOuVazio.where((i) => i.estoqueEntradaRegistrada).toList();



  static Future<(bool, List<String>)> _validarPipelineConcluido(

    String lojaId,

    CompraFornecedor compra,

  ) async {

    if (!CompraFornecedorTipo.movimentaEstoque(compra.tipoCompra)) {

      return (false, const <String>[]);

    }

    final pBox = await CompraItemPipelineStore.openBox(lojaId);

    if (pBox == null) return (false, const <String>[]);



    final semSnapshot = <String>[];

    for (final row in pBox.values) {

      if (row.compraId.trim() != compra.id.trim()) continue;

      if (row.estado != CompraItemPipelineEstado.concluidoNoEstoque) continue;

      final itemId = row.itemCompraId.trim();

      CompraFornecedorItem? item;

      for (final it in compra.itensOuVazio) {

        if (it.itemCompraId.trim() == itemId) {

          item = it;

          break;

        }

      }

      if (item == null || !item.estoqueSnapshotOk) {

        semSnapshot.add(row.nomeProdutoProvisorio);

      }

    }

    return (semSnapshot.isNotEmpty, semSnapshot);

  }



  static Future<ResultadoCancelamentoCompra> cancelar({

    required String lojaId,

    required String compraId,

    String motivo = '',

  }) async {

    final lid = lojaId.trim();

    final cid = compraId.trim();

    if (lid.isEmpty || cid.isEmpty) {

      return ResultadoCancelamentoCompra.erro('Loja ou compra inválida.');

    }



    final compraBox = await CompraFornecedorHiveStore.openBox(lid);

    if (compraBox == null) {

      return ResultadoCancelamentoCompra.erro('Armazenamento da compra indisponível.');

    }



    var compra = compraBox.get(cid);

    if (compra == null) {

      return ResultadoCancelamentoCompra.erro('Compra não encontrada.');

    }

    if (compra.estaCancelada) {

      return ResultadoCancelamentoCompra(

        sucesso: true,

        mensagem: 'Compra já estava cancelada.',

        compraAtualizada: compra,

      );

    }



    final itensEntrada = _itensComEntradaEstoque(compra);

    final (pipelineBloqueia, nomesPipeline) =

        await _validarPipelineConcluido(lid, compra);



    if (pipelineBloqueia) {

      return ResultadoCancelamentoCompra.erro(

        '$_msgSemSnapshot\n'

        'Itens no estoque via pipeline sem snapshot: ${nomesPipeline.join(', ')}.',

      );

    }



    if (itensEntrada.any((i) => !i.estoqueSnapshotOk)) {

      return ResultadoCancelamentoCompra.erro(_msgSemSnapshot);

    }



    final prodBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaId));



    if (itensEntrada.isNotEmpty) {

      final pre = await _preValidarEstornoItens(prodBox, itensEntrada);

      if (pre != null) return pre;

    }



    var estoqueEstornado = false;

    final custosNaoRestaurados = <String>[];

    if (itensEntrada.isNotEmpty) {

      final est = await _estornarItens(

        lojaId: lojaId,

        compra: compra,

        itens: itensEntrada,

        prodBox: prodBox,

        custosNaoRestaurados: custosNaoRestaurados,

      );

      if (!est.sucesso) return est;

      estoqueEstornado = true;

      compra = est.compraAtualizada ?? compra;

    }



    final parcelasCanceladas = await _cancelarContasPagar(lid, cid);



    final now = DateTime.now();

    compra = compra.copyWith(

      statusCompra: CompraFornecedorStatusCompra.cancelada,

      canceladaEm: now,

      canceladaMotivo: motivo.trim(),

      cancelamentoEstoqueAplicado: estoqueEstornado,

      atualizadoEm: now,

      syncPendente: true,

    );



    await compraBox.put(compra.id, compra);



    if (CompraFornecedorTipo.movimentaEstoque(compra.tipoCompra)) {

      await CompraParaPipelineService.sincronizarCancelamentoCompraNoPipeline(

        compra,

      );

    }

    CompraFinanceiroIntegracaoService.aplicarEfeitosCancelamento(compra);



    try {

      await CompraFornecedorFirestoreService.upsertCompra(compra);

    } catch (e) {

      debugPrint('[COMPRA-CANC] Sync FS falhou: $e');

    }



    var msg = estoqueEstornado

        ? 'Compra cancelada e estoque estornado.'

        : 'Compra cancelada.';

    if (custosNaoRestaurados.isNotEmpty) {

      msg += ' Custo não restaurado automaticamente em: '

          '${custosNaoRestaurados.join(', ')} (houve alteração posterior).';

    }



    return ResultadoCancelamentoCompra(

      sucesso: true,

      mensagem: msg,

      estoqueEstornado: estoqueEstornado,

      parcelasCanceladas: parcelasCanceladas,

      compraAtualizada: compra,

      custosNaoRestaurados: List.unmodifiable(custosNaoRestaurados),

    );

  }



  /// Validação prévia — sem alterar CP, compra nem estoque.

  static Future<ResultadoCancelamentoCompra?> _preValidarEstornoItens(

    Box<Produto> prodBox,

    List<CompraFornecedorItem> itens,

  ) async {

    for (final item in itens) {

      var tam = item.tamanhoEntrada.trim();

      var cor = item.corEntrada.trim();

      if (tam.isEmpty && cor.isEmpty) {

        final parsed =

            CompraFornecedorEstornoSnapshot.parseTamCorObservacao(item.observacaoItem);

        tam = parsed.tam;

        cor = parsed.cor;

      }



      final produto = _resolverProduto(prodBox, item);

      if (produto == null) {

        return ResultadoCancelamentoCompra.erro(

          'Produto não encontrado para estorno: ${item.produtoNome}',

        );

      }



      if (!CompraFornecedorEstornoSnapshot.estoqueSuficienteParaEstorno(

        produto,

        item,

        tamanho: tam,

        cor: cor,

      )) {

        return ResultadoCancelamentoCompra.erro(_msgEstoqueInsuficiente);

      }

    }

    return null;

  }



  static Produto? _resolverProduto(Box<Produto> prodBox, CompraFornecedorItem item) {

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



  static Future<ResultadoCancelamentoCompra> _estornarItens({

    required String lojaId,

    required CompraFornecedor compra,

    required List<CompraFornecedorItem> itens,

    required Box<Produto> prodBox,

    required List<String> custosNaoRestaurados,

  }) async {

    final itensAtualizados = List<CompraFornecedorItem>.from(compra.itensOuVazio);



    for (final item in itens) {

      final idx = itensAtualizados.indexWhere(

        (x) => x.itemCompraId == item.itemCompraId,

      );

      if (idx < 0) continue;



      var tam = item.tamanhoEntrada.trim();

      var cor = item.corEntrada.trim();

      if (tam.isEmpty && cor.isEmpty) {

        final parsed =

            CompraFornecedorEstornoSnapshot.parseTamCorObservacao(item.observacaoItem);

        tam = parsed.tam;

        cor = parsed.cor;

      }



      final produto = _resolverProduto(prodBox, item);

      if (produto == null) {

        return ResultadoCancelamentoCompra.erro(

          'Produto não encontrado para estorno: ${item.produtoNome}',

        );

      }



      final est = await EstoqueService.atualizarEstoque(

        produtosBox: prodBox,

        lojaId: lojaId,

        produtoId: produto.idFirebase.isNotEmpty ? produto.idFirebase : null,

        produtoNome: produto.nome,

        produtoSlug: produto.slug,

        tamanho: tam,

        cor: cor,

        quantidade: item.quantidade,

        operacao: EstoqueOperacaoCompra.estornoCompra,

      );

      if (!est.sucesso) {

        return ResultadoCancelamentoCompra.erro(est.mensagem);

      }



      final produtoPosEstorno = _resolverProduto(prodBox, item) ?? produto;

      if (CompraFornecedorEstornoSnapshot.podeRestaurarCusto(
        item,
        produtoPosEstorno,
      )) {
        produtoPosEstorno.custoReal = item.custoAnterior;
        await produtoPosEstorno.save();
      } else {
        custosNaoRestaurados.add(produtoPosEstorno.nome);
      }

      if (item.produtoNovoNaCompra) {
        produtoPosEstorno.ativoNoRascunho = false;
        await produtoPosEstorno.save();
      }



      var obs = itensAtualizados[idx].observacaoItem;

      if (!obs.contains('origemCompraCancelada:')) {

        obs = obs.trim().isEmpty

            ? 'origemCompraCancelada:${compra.id}'

            : '$obs · origemCompraCancelada:${compra.id}';

      }

      itensAtualizados[idx] = itensAtualizados[idx].copyWith(

        estoqueEntradaRegistrada: false,

        observacaoItem: obs,

      );

    }



    return ResultadoCancelamentoCompra(

      sucesso: true,

      compraAtualizada: compra.copyWith(itens: itensAtualizados),

    );

  }



  static Future<int> _cancelarContasPagar(String lojaId, String compraId) async {

    final cpBox = await ContaPagarHiveStore.openBox(lojaId);

    if (cpBox == null) return 0;



    final parcelas = ContaPagarService.listar(cpBox, lojaId, compraId: compraId)

        .where((c) => c.status != ContaPagarStatus.cancelado)

        .toList();



    var n = 0;

    for (final cp in parcelas) {

      final r = await ContaPagarFinanceiroExclusaoService.cancelarContaPagar(

        lojaId: lojaId,

        conta: cp,

        excluirLancamentoVinculado: true,

      );

      if (r.contaCancelada && !r.jaEstavaCancelada) n++;

    }

    return n;

  }

}


