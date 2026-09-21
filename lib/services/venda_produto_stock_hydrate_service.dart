// Hidrata produto do Hive com estoque remoto antes da venda (read + cache local).
// Sem writes remotos. Não sobrescreve pending REAL.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/produto_effective_stock.dart';
import '../core/produto_estoque_grade_snapshot.dart';
import '../core/produto_stock_revision.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';
import 'produtos_firestore_service.dart';

class VendaProdutoStockHydrateService {
  VendaProdutoStockHydrateService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(String lojaId, String docId)?
      debugRemoteReader;

  static FirebaseFirestore get _db =>
      debugFirestoreOverride ??
      ProdutosFirestoreService.debugFirestoreOverride ??
      FirebaseFirestore.instance;

  /// Busca `estoque_produtos` e aplica no [produto] se não houver pending.
  /// Persiste no Hive se [produto.isInBox].
  static Future<bool> hydrateProdutoFromRemoteEstoque({
    required String lojaId,
    required Produto produto,
  }) async {
    final li = lojaId.trim();
    final docId = produto.idFirebase.trim();
    if (li.isEmpty || docId.isEmpty) return false;
    if (hasPendingStockMutation(produto)) return false;

    Map<String, dynamic>? data;
    if (debugRemoteReader != null) {
      data = await debugRemoteReader!(li, docId);
    } else {
      final snap = await _db
          .collection('lojas')
          .doc(li)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      if (!snap.exists) return false;
      data = snap.data();
    }
    if (data == null) return false;

    final applied = applyAuthoritativeRemoteStockToProduto(
      produto,
      remote: data,
      updateQuantity: true,
    );
    if (!applied) return false;
    if (produto.isInBox) {
      await produto.save();
    }
    return true;
  }

  /// True se o produto (já hidratado) exige picker de variação.
  static bool requiresVariationPicker(Produto p) {
    final kind = effectiveStockKindFromProduto(p);
    if (kind != EffectiveStockKind.variation &&
        kind != EffectiveStockKind.grade) {
      return false;
    }
    final cells = normalizeSemCorAliasCells(
      ProdutoEstoqueGradeSnapshot.fromProduto(p).cells,
    );
    return saleOptionsFromNormalizedCells(cells).isNotEmpty;
  }

  @visibleForTesting
  static void resetForTests() {
    debugFirestoreOverride = null;
    debugRemoteReader = null;
  }
}
