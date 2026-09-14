// Sincronização imediata do catálogo web (draft → live) após qualquer mutação
// real de estoque. Não bloqueia venda se falhar — apenas registra.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../models/produto.dart';
import 'catalog_cache_service.dart';
import 'catalog_publish_service.dart';
import 'stock_catalog_backend_service.dart';
import 'catalogo_sync_service.dart';
import 'combo_kit_stock_service.dart';
import 'estoque_transaction_service.dart';

class CatalogoWebAposEstoqueService {
  CatalogoWebAposEstoqueService._();

  @visibleForTesting
  static Duration? debugCatalogSyncDelay;

  /// Hook de teste: lança / observa antes de sync+promote (não reexecuta baixa).
  @visibleForTesting
  static Future<void> Function(String productId)? debugBeforeProductSync;

  /// Hook de teste: corre antes de ler pendências no Hive (ex.: simular falha).
  @visibleForTesting
  static Future<void> Function()? debugBeforeLerPendencias;

  @visibleForTesting
  static void debugClearOverrides() {
    debugCatalogSyncDelay = null;
    debugBeforeProductSync = null;
    debugBeforeLerPendencias = null;
  }

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

  /// Reexecuta só draft→live dos IDs persistidos após falha.
  /// Não registra venda nem baixa estoque. Pendência sobrevive ao fechar o app
  /// (Hive `config`). Chamado na abertura do Estoque e no próximo sync.
  static Future<void> tentarRecuperarPendencias({
    String? lojaId,
    Box<Produto>? produtosBox,
  }) async {
    try {
      final beforeRead = debugBeforeLerPendencias;
      if (beforeRead != null) {
        await beforeRead();
      }
      final pendencias =
          await CatalogPublishService.lerPendenciasSyncAposEstoque();
      if (pendencias.isEmpty) return;

      final filtro = lojaId?.trim();
      final alvos = (filtro != null && filtro.isNotEmpty)
          ? {filtro: pendencias[filtro] ?? <String>{}}
          : pendencias;

      for (final e in alvos.entries) {
        if (e.value.isEmpty) continue;
        var box = produtosBox;
        if (box == null) {
          try {
            final name = HiveBoxNames.produtos(e.key);
            if (!Hive.isBoxOpen(name)) {
              await Hive.openBox<Produto>(name);
            }
            box = Hive.box<Produto>(name);
          } catch (err, st) {
            logE(
              '[CAT-WEB-ESTOQUE] Falha ao abrir Hive para recuperar pendências '
              '(loja=${e.key}) (type=${err.runtimeType})',
              error: err,
              st: st,
            );
            continue;
          }
        }
        try {
          await sincronizarCatalogoWebAposMudancaEstoque(
            lojaId: e.key,
            productIdsAfetados: e.value,
            produtosBox: box,
          );
        } catch (err, st) {
          logE(
            '[CAT-WEB-ESTOQUE] Falha ao sincronizar pendências '
            '(loja=${e.key}) (type=${err.runtimeType})',
            error: err,
            st: st,
          );
        }
      }
    } catch (e, st) {
      logE(
        '[CAT-WEB-ESTOQUE] Falha ao recuperar pendências de catálogo '
        '(type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
  }

  /// Atualiza `draft_produtos` a partir do Hive e promove para `produtos` (web)
  /// para cada [productId] canônico afetado. Falhas são logadas e não propagadas.
  static Future<void> sincronizarCatalogoWebAposMudancaEstoque({
    required String lojaId,
    required Set<String> productIdsAfetados,
    required Box<Produto> produtosBox,
  }) async {
    final li = lojaId.trim();
    if (li.isEmpty) return;

    final ids = productIdsAfetados
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    try {
      final pendentes = await CatalogPublishService.lerPendenciasSyncAposEstoque();
      ids.addAll(pendentes[li] ?? const <String>{});
    } catch (e, st) {
      logE(
        '[CAT-WEB-ESTOQUE] Falha ao ler pendências de sync (type=${e.runtimeType})',
        error: e,
        st: st,
      );
    }
    if (ids.isEmpty) return;

    final alvo = _expandirComIdsDeCombosAfetados(
      lojaId: li,
      produtosBox: produtosBox,
      base: ids,
    );


    for (final pid in alvo) {
      try {
        final delay = debugCatalogSyncDelay;
        if (delay != null && delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        final beforeSync = debugBeforeProductSync;
        if (beforeSync != null) {
          await beforeSync(pid);
        }
        if (CatalogPublishService.usaBackendConfiavel) {
          await StockCatalogBackendService.publishOne(li, pid);
        } else {
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
        await CatalogoSyncService.removerCopiaLegadaCatalogoSeMesmoProduto(
          lojaId: li,
          pdt: p,
        );
        }
        try {
          await CatalogPublishService.removerPendenciaSyncAposEstoque(
            lojaId: li,
            productIds: [pid],
          );
        } catch (e2, st2) {
          logE(
            '[CAT-WEB-ESTOQUE] Falha ao limpar pendência de sync (productId=$pid) '
            '(type=${e2.runtimeType})',
            error: e2,
            st: st2,
          );
        }
      } catch (e, st) {
        logE(
          '[CAT-WEB-ESTOQUE] Falha ao sincronizar catálogo web após estoque (productId=$pid) (type=${e.runtimeType})',
          error: e,
          st: st,
        );
        try {
          await CatalogPublishService.registrarPendenciaSyncAposEstoque(
            lojaId: li,
            productIds: [pid],
          );
        } catch (e2, st2) {
          logE(
            '[CAT-WEB-ESTOQUE] Falha ao marcar catálogo para atualização (type=${e2.runtimeType})',
            error: e2,
            st: st2,
          );
        }
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
