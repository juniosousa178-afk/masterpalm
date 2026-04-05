// Sincronização imediata do catálogo web (draft → live) após qualquer mutação
// real de estoque. Não bloqueia venda se falhar — apenas registra.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../models/produto.dart';
import 'catalog_cache_service.dart';
import 'catalog_publish_service.dart';
import 'catalogo_sync_service.dart';
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';

class CatalogoWebAposEstoqueService {
  CatalogoWebAposEstoqueService._();

  /// IDs canônicos a partir dos resultados da transação de estoque.
  static Set<String> _idsDeResultados(List<EstoqueTransactionResult> results) {
    return ComboKitStockService.produtoIdsDeResultadosBaixa(results);
  }

  /// Inclui SKUs de combo cuja receita ou estoque foi afetada pelos ids [base].
  static Set<String> _expandirComIdsDeCombosAfetados({
    required String lojaId,
    required Box<Produto> produtosBox,
    required Set<String> base,
  }) {
    if (base.isEmpty) return base;
    final out = Set<String>.from(base);
    final combos = ComboKitStockService.combosAfetadosPorProductIdsDebitados(
      lojaId: lojaId,
      produtosBox: produtosBox,
      debitedIds: base,
    );
    for (final c in combos) {
      final id = c.idFirebase.trim();
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  static Produto? _produtoPorIdFirebase(
    Box<Produto> box,
    String lojaId,
    String productId,
  ) {
    final t = productId.trim();
    if (t.isEmpty) return null;
    for (final p in box.values) {
      if (p.lojaId == lojaId && p.idFirebase.trim() == t) return p;
    }
    return null;
  }

  /// Atualiza `draft_produtos` a partir do Hive e promove para `produtos` (web)
  /// para cada [productId] canônico afetado. Falhas são logadas e não propagadas.
  static Future<void> sincronizarCatalogoWebAposMudancaEstoque({
    required String lojaId,
    required Set<String> productIdsAfetados,
    required Box<Produto> produtosBox,
  }) async {
    final li = lojaId.trim();
    if (li.isEmpty || productIdsAfetados.isEmpty) return;

    final alvo = _expandirComIdsDeCombosAfetados(
      lojaId: li,
      produtosBox: produtosBox,
      base: productIdsAfetados.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
    );

    for (final pid in alvo) {
      try {
        final p = _produtoPorIdFirebase(produtosBox, li, pid);
        if (p == null) {
          if (kDebugMode) {
            debugPrint(
              '[CAT-WEB-ESTOQUE] Produto não encontrado no Hive (id=$pid); pulando sync catálogo.',
            );
          }
          continue;
        }

        await CatalogoSyncService.syncProduto(
          p,
          target: SyncTarget.draft,
          lojaIdOverride: li,
        );

        final docId = CatalogoSyncService.catalogFirestoreDocId(p);
        await CatalogPublishService.promoteOne(docId, lojaIdOverride: li);
      } catch (e, st) {
        logE(
          '[CAT-WEB-ESTOQUE] Falha ao sincronizar catálogo web após estoque (productId=$pid) (type=${e.runtimeType})',
          error: e,
          st: st,
        );
      }
    }

    try {
      CatalogCacheService.invalidate(li, preview: false);
      CatalogCacheService.invalidate(li, preview: true);
    } catch (e, st) {
      logE(
        '[CAT-WEB-ESTOQUE] Falha ao invalidar cache (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }

  /// Conveniência: extrai ids dos resultados (venda + ajuste de teto de combo) e sincroniza.
  static Future<void> sincronizarAposResultadosTransacao({
    required String lojaId,
    required Box<Produto> produtosBox,
    required List<EstoqueTransactionResult> resultadosPrincipais,
    List<EstoqueTransactionResult> resultadosComboExtra = const [],
  }) async {
    final merged = <EstoqueTransactionResult>[
      ...resultadosPrincipais,
      ...resultadosComboExtra,
    ];
    if (merged.isEmpty) return;
    final ids = _idsDeResultados(merged);
    await sincronizarCatalogoWebAposMudancaEstoque(
      lojaId: lojaId,
      productIdsAfetados: ids,
      produtosBox: produtosBox,
    );
  }
}
