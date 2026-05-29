// Espelho de compra de fornecedor no Firestore — política em CompraFinanceiroIntegracaoService.
// Caminho: lojas/{lojaId}/compras_fornecedor/{compraId}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';
import '../models/compra_fornecedor_item.dart';
import 'compra_financeiro_integracao_service.dart';

class CompraFornecedorFirestoreService {
  CompraFornecedorFirestoreService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ?? FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> docRef(
    String lojaId,
    String compraId,
  ) {
    return _db
        .collection('lojas')
        .doc(lojaId.trim())
        .collection('compras_fornecedor')
        .doc(compraId.trim());
  }

  /// Idempotente: mesmo [compraId] sobrescreve/atualiza o mesmo documento com merge.
  static Future<void> upsertCompra(CompraFornecedor c) async {
    final lid = c.lojaId.trim();
    final cid = c.id.trim();
    if (lid.isEmpty || cid.isEmpty) return;

    final data = compraParaMap(c);
    await docRef(lid, cid).set(data, SetOptions(merge: true));
    debugPrint('✅ [COMPRA-FS] upsert compra $cid');
  }

  /// Lê compra espelhada no Firestore (Hive continua fonte operacional local).
  static Future<CompraFornecedor?> lerCompra(
    String lojaId,
    String compraId,
  ) async {
    final snap = await docRef(lojaId, compraId).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return compraFromMap(data, fallbackCompraId: compraId);
  }

  @visibleForTesting
  static Map<String, dynamic> compraParaMap(CompraFornecedor c) =>
      _compraParaMap(c);

  @visibleForTesting
  static CompraFornecedor? compraFromMap(
    Map<String, dynamic> data, {
    String? fallbackCompraId,
  }) {
    try {
      final id = (data['compraId'] ?? fallbackCompraId ?? '').toString().trim();
      final lojaId = (data['lojaId'] ?? '').toString().trim();
      if (id.isEmpty || lojaId.isEmpty) return null;

      final itensRaw = data['itens'];
      final itens = <CompraFornecedorItem>[];
      if (itensRaw is List) {
        for (final raw in itensRaw) {
          if (raw is Map) {
            final item = itemFromMap(Map<String, dynamic>.from(raw));
            if (item != null) itens.add(item);
          }
        }
      }

      return CompraFornecedor(
        id: id,
        lojaId: lojaId,
        fornecedorHiveKey: (data['fornecedorHiveKey'] as num?)?.toInt() ?? 0,
        fornecedorNome: (data['fornecedorNome'] ?? '').toString(),
        referenciaInterna: (data['referenciaInterna'] ?? '').toString(),
        dataCompra: _tsToDate(data['dataCompra']) ?? DateTime.now(),
        dataVencimento: _tsToDate(data['dataVencimento']),
        statusCompra: CompraFornecedorStatusCompra.ouPadrao(
          (data['statusCompra'] ?? '').toString(),
        ),
        statusPagamento: CompraFornecedorStatusPagamento.ouPadrao(
          (data['statusPagamento'] ?? '').toString(),
        ),
        observacao: (data['observacao'] ?? '').toString(),
        frete: (data['frete'] as num?)?.toDouble() ?? 0,
        desconto: (data['desconto'] as num?)?.toDouble() ?? 0,
        outrasDespesas: (data['outrasDespesas'] as num?)?.toDouble() ?? 0,
        valorPago: (data['valorPago'] as num?)?.toDouble() ?? 0,
        itens: itens.isEmpty ? null : itens,
        estoqueIntegrado: data['estoqueIntegrado'] == true,
        idLancamentoFinanceiro:
            (data['idLancamentoFinanceiro'] ?? '').toString(),
        confirmadoEm: _tsToDate(data['confirmadoEm']),
        criadoEm: _tsToDate(data['criadoEm']) ?? DateTime.now(),
        atualizadoEm: _tsToDate(data['atualizadoEm']) ?? DateTime.now(),
        syncPendente: data['syncPendente'] != false,
        syncStatus: (data['syncStatus'] ?? 'pendente').toString(),
        tipoCompra: CompraFornecedorTipo.ouPadrao(
          (data['tipoCompra'] ?? '').toString(),
        ),
        valorInformado: (data['valorInformado'] as num?)?.toDouble() ?? 0,
        statusDetalhamentoProdutos:
            CompraFornecedorStatusDetalhamento.ouPadrao(
          (data['statusDetalhamentoProdutos'] ?? '').toString(),
        ),
        detalhamentoProdutosAt: _tsToDate(data['detalhamentoProdutosAt']),
        detalhamentoProdutosConferidoAt:
            _tsToDate(data['detalhamentoProdutosConferidoAt']),
        valorProdutosDetalhados:
            (data['valorProdutosDetalhados'] as num?)?.toDouble() ?? 0,
        diferencaDetalhamento:
            (data['diferencaDetalhamento'] as num?)?.toDouble() ?? 0,
        quantidadeItensDetalhados:
            (data['quantidadeItensDetalhados'] as num?)?.toInt() ?? 0,
        observacaoDetalhamento:
            (data['observacaoDetalhamento'] ?? '').toString(),
        canceladaEm: _tsToDate(data['canceladaEm']),
        canceladaMotivo: (data['canceladaMotivo'] ?? '').toString(),
        cancelamentoEstoqueAplicado: data['cancelamentoEstoqueAplicado'] == true,
      );
    } catch (e) {
      debugPrint('[COMPRA-FS] Parse compra remota falhou (type=${e.runtimeType})');
      return null;
    }
  }

  @visibleForTesting
  static CompraFornecedorItem? itemFromMap(Map<String, dynamic> m) {
    try {
      final obs = (m['observacaoItem'] ?? m['observacao'] ?? '').toString();
      final cod = (m['codigo'] ?? '').toString();
      return CompraFornecedorItem(
        produtoNome: (m['produtoNome'] ?? '').toString(),
        quantidade: (m['quantidade'] as num?)?.toInt() ?? 0,
        custoUnitario: (m['custoUnitarioBase'] as num?)?.toDouble() ??
            (m['custoUnitario'] as num?)?.toDouble() ??
            0,
        productId: (m['productId'] ?? m['produtoId'])?.toString(),
        itemCompraId: (m['itemCompraId'] ?? '').toString(),
        codigoInterno: cod,
        observacaoItem: obs,
        unidade: (m['unidade'] ?? '').toString(),
        subtotalBase: (m['subtotalBase'] as num?)?.toDouble() ?? 0,
        percentualParticipacao:
            (m['percentualParticipacao'] as num?)?.toDouble() ?? 0,
        freteRateado: (m['freteRateado'] as num?)?.toDouble() ?? 0,
        descontoRateado: (m['descontoRateado'] as num?)?.toDouble() ?? 0,
        outrasDespesasRateadas:
            (m['outrasDespesasRateadas'] as num?)?.toDouble() ?? 0,
        custoUnitarioFinal: (m['custoUnitarioFinal'] as num?)?.toDouble() ?? 0,
        subtotalFinal: (m['subtotalFinal'] as num?)?.toDouble() ?? 0,
        estoqueEntradaRegistrada: m['estoqueEntradaRegistrada'] == true,
        estoqueSnapshotOk: m['estoqueSnapshotOk'] == true,
        estoqueAnterior: (m['estoqueAnterior'] as num?)?.toInt() ?? 0,
        custoAnterior: (m['custoAnterior'] as num?)?.toDouble() ?? 0,
        tamanhoEntrada: (m['tamanhoEntrada'] ?? '').toString(),
        corEntrada: (m['corEntrada'] ?? '').toString(),
        produtoNovoNaCompra: m['produtoNovoNaCompra'] == true,
        custoEntradaRegistrado:
            (m['custoEntradaRegistrado'] as num?)?.toDouble() ?? 0,
      );
    } catch (e) {
      debugPrint('[COMPRA-FS] Parse item remoto falhou (type=${e.runtimeType})');
      return null;
    }
  }

  static DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is DateTime) return v;
    return null;
  }

  static Map<String, dynamic> _compraParaMap(CompraFornecedor c) {
    final itens = c.itensOuVazio.map(_itemParaMap).toList();
    return <String, dynamic>{
      'compraId': c.id,
      'lojaId': c.lojaId,
      'fornecedorHiveKey': c.fornecedorHiveKey,
      'fornecedorNome': c.fornecedorNome,
      'referenciaInterna': c.referenciaInterna,
      'dataCompra': Timestamp.fromDate(c.dataCompra.toUtc()),
      'dataVencimento': c.dataVencimento != null
          ? Timestamp.fromDate(c.dataVencimento!.toUtc())
          : null,
      'statusCompra': c.statusCompra,
      'statusPagamento': c.statusPagamento,
      'observacao': c.observacao,
      'subtotalItensBase': c.subtotalItensBase,
      'frete': c.frete,
      'desconto': c.desconto,
      'outrasDespesas': c.outrasDespesas,
      'valorTotalFinanceiro': c.valorTotalFinanceiro,
      'valorPago': c.valorPago,
      'valorEmAberto': c.valorEmAberto,
      'estoqueIntegrado': c.estoqueIntegrado,
      'idLancamentoFinanceiro': c.idLancamentoFinanceiro.trim(),
      'lancamentoFinanceiroDocIdCanonica':
          CompraFinanceiroIntegracaoService.docIdLancamentoCanonica(c.id),
      'financeiroSemDespesaAutomaticaPorTotalCompra':
          !CompraFinanceiroIntegracaoService.permiteLancamentoAutomaticoPeloTotalDaCompra,
      'confirmadoEm': c.confirmadoEm != null
          ? Timestamp.fromDate(c.confirmadoEm!.toUtc())
          : null,
      'criadoEm': Timestamp.fromDate(c.criadoEm.toUtc()),
      'atualizadoEm': Timestamp.fromDate(c.atualizadoEm.toUtc()),
      'syncPendente': c.syncPendente,
      'syncStatus': c.syncStatus,
      'itens': itens,
      'tipoCompra': CompraFornecedorTipo.ouPadrao(c.tipoCompra),
      'valorInformado': c.valorInformado,
      'statusDetalhamentoProdutos': c.statusDetalhamentoProdutos,
      'detalhamentoProdutosAt': c.detalhamentoProdutosAt != null
          ? Timestamp.fromDate(c.detalhamentoProdutosAt!.toUtc())
          : null,
      'detalhamentoProdutosConferidoAt':
          c.detalhamentoProdutosConferidoAt != null
              ? Timestamp.fromDate(c.detalhamentoProdutosConferidoAt!.toUtc())
              : null,
      'valorProdutosDetalhados': c.valorProdutosDetalhados,
      'diferencaDetalhamento': c.diferencaDetalhamento,
      'quantidadeItensDetalhados': c.quantidadeItensDetalhados,
      'observacaoDetalhamento': c.observacaoDetalhamento,
      if (c.canceladaEm != null)
        'canceladaEm': Timestamp.fromDate(c.canceladaEm!.toUtc()),
      'canceladaMotivo': c.canceladaMotivo,
      'cancelamentoEstoqueAplicado': c.cancelamentoEstoqueAplicado,
      'schemaVersion': 3,
    };
  }

  static Map<String, dynamic> _itemParaMap(CompraFornecedorItem it) {
    final cod = it.codigoInterno.trim().isNotEmpty
        ? it.codigoInterno.trim()
        : (it.codigoBarras.trim().isNotEmpty ? it.codigoBarras.trim() : null);
    final estoqueDepois = it.estoqueEntradaRegistrada
        ? it.estoqueAnterior + it.quantidade
        : null;
    return <String, dynamic>{
      'itemCompraId': it.itemCompraId,
      'produtoNome': it.produtoNome,
      if (cod != null) 'codigo': cod,
      'quantidade': it.quantidade,
      'custoUnitarioBase': it.custoUnitario,
      'subtotalBase': it.subtotalBase,
      'percentualParticipacao': it.percentualParticipacao,
      'freteRateado': it.freteRateado,
      'descontoRateado': it.descontoRateado,
      'outrasDespesasRateadas': it.outrasDespesasRateadas,
      'custoUnitarioFinal': it.custoUnitarioFinal,
      'subtotalFinal': it.subtotalFinal,
      if (it.productId != null && it.productId!.trim().isNotEmpty)
        'productId': it.productId!.trim(),
      if (it.observacaoItem.trim().isNotEmpty) ...{
        'observacao': it.observacaoItem,
        'observacaoItem': it.observacaoItem,
      },
      if (it.unidade.trim().isNotEmpty) 'unidade': it.unidade,
      'estoqueEntradaRegistrada': it.estoqueEntradaRegistrada,
      'estoqueSnapshotOk': it.estoqueSnapshotOk,
      'estoqueAnterior': it.estoqueAnterior,
      if (estoqueDepois != null) 'estoqueDepois': estoqueDepois,
      'custoAnterior': it.custoAnterior,
      if (it.tamanhoEntrada.trim().isNotEmpty) 'tamanhoEntrada': it.tamanhoEntrada,
      if (it.corEntrada.trim().isNotEmpty) 'corEntrada': it.corEntrada,
      'produtoNovoNaCompra': it.produtoNovoNaCompra,
      'custoEntradaRegistrado': it.custoEntradaRegistrado,
    };
  }
}
