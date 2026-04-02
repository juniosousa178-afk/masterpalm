// Espelho de compra de fornecedor no Firestore — sem lançamento financeiro automático.
// Caminho: lojas/{lojaId}/compras_fornecedor/{compraId}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_item.dart';

class CompraFornecedorFirestoreService {
  CompraFornecedorFirestoreService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

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

    final data = _compraParaMap(c);
    await docRef(lid, cid).set(data, SetOptions(merge: true));
    debugPrint('✅ [COMPRA-FS] upsert compra $cid');
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
      'confirmadoEm': c.confirmadoEm != null
          ? Timestamp.fromDate(c.confirmadoEm!.toUtc())
          : null,
      'criadoEm': Timestamp.fromDate(c.criadoEm.toUtc()),
      'atualizadoEm': Timestamp.fromDate(c.atualizadoEm.toUtc()),
      'syncPendente': c.syncPendente,
      'syncStatus': c.syncStatus,
      'itens': itens,
      'schemaVersion': 1,
    };
  }

  static Map<String, dynamic> _itemParaMap(CompraFornecedorItem it) {
    final cod = it.codigoInterno.trim().isNotEmpty
        ? it.codigoInterno.trim()
        : (it.codigoBarras.trim().isNotEmpty ? it.codigoBarras.trim() : null);
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
      if (it.observacaoItem.trim().isNotEmpty) 'observacao': it.observacaoItem,
      if (it.unidade.trim().isNotEmpty) 'unidade': it.unidade,
    };
  }
}
