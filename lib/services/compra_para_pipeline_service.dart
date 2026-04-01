// lib/services/compra_para_pipeline_service.dart
// Materialização idempotente: compra confirmada → CompraItemPipeline (Hive).

import '../core/compra_item_pipeline_constants.dart';
import '../models/compra_fornecedor.dart';
import '../models/compra_fornecedor_constants.dart';
import '../models/compra_fornecedor_item.dart';
import '../models/compra_item_pipeline.dart';
import 'compra_item_pipeline_store.dart';

class CompraParaPipelineService {
  CompraParaPipelineService._();

  /// Garante uma linha por (compraId, itemCompraId). Não cria financeiro nem Produto.
  static Future<void> sincronizarItensCompraConfirmada(
    CompraFornecedor compra,
  ) async {
    if (compra.statusCompra != CompraFornecedorStatusCompra.confirmada) return;
    final lid = compra.lojaId.trim();
    if (lid.isEmpty) return;

    final box = await CompraItemPipelineStore.openBox(lid);
    if (box == null) return;

    final now = DateTime.now();
    for (final it in compra.itensOuVazio) {
      final itemId = it.itemCompraId.trim();
      if (itemId.isEmpty) continue;

      final docId = CompraItemPipeline.docId(compra.id, itemId);
      final existing = box.get(docId);

      if (existing != null) {
        if (existing.estado == CompraItemPipelineEstado.cancelado) continue;
        if (existing.estado == CompraItemPipelineEstado.concluidoNoEstoque) {
          continue;
        }
        final merged = existing.copyWith(
          nomeProdutoProvisorio: it.produtoNome,
          quantidade: it.quantidade,
          custoUnitario: it.custoUnitario,
          codigoInterno: it.codigoInterno,
          codigoBarras: it.codigoBarras.isNotEmpty
              ? it.codigoBarras
              : existing.codigoBarras,
          observacaoItem: it.observacaoItem,
          unidade: it.unidade.isNotEmpty ? it.unidade : existing.unidade,
          productIdFirebase: it.productId?.isNotEmpty == true
              ? it.productId
              : existing.productIdFirebase,
          fornecedorNome: compra.fornecedorNome,
          referenciaCompra: compra.referenciaInterna,
          atualizadoEm: now,
        );
        await box.put(docId, merged);
        continue;
      }

      final novo = CompraItemPipeline(
        id: docId,
        lojaId: lid,
        compraId: compra.id,
        itemCompraId: itemId,
        fornecedorNome: compra.fornecedorNome,
        referenciaCompra: compra.referenciaInterna,
        nomeProdutoProvisorio: it.produtoNome,
        quantidade: it.quantidade,
        custoUnitario: it.custoUnitario,
        codigoInterno: it.codigoInterno,
        codigoBarras: it.codigoBarras,
        observacaoItem: it.observacaoItem,
        unidade: it.unidade,
        productIdFirebase:
            it.productId != null && it.productId!.trim().isNotEmpty
                ? it.productId!.trim()
                : null,
        estado: CompraItemPipelineEstado.aguardandoPrecificacao,
        atualizadoEm: now,
      );
      await box.put(docId, novo);
    }
  }
}
