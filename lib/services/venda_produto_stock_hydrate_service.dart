// Hidrata produto do Hive com estoque remoto antes da venda (read + cache local).
// Sem writes remotos. Não sobrescreve qty/revision quando há pending REAL.
// Mesmo com pending: aplica estrutura de variação só para UI do picker.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/produto_effective_stock.dart';
import '../core/produto_estoque_grade_snapshot.dart';
import '../core/produto_sale_variation_picker.dart';
import '../core/produto_stock_revision.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';
import 'produtos_firestore_service.dart';

enum SaleVariationRouteDecision {
  /// Adicionar como simple (sem variationKey).
  addAsSimple,

  /// Abrir picker de variação (opções reais).
  openVariationPicker,

  /// Produto variável sem opções utilizáveis — não adicionar.
  failClosed,
}

class SaleVariationRouteResult {
  const SaleVariationRouteResult({
    required this.decision,
    required this.produto,
    this.remote,
    this.options = const [],
    this.effectiveKindWire = 'simple',
  });

  final SaleVariationRouteDecision decision;
  final Produto produto;
  final Map<String, dynamic>? remote;
  final List<ProdutoSaleVariationOption> options;
  final String effectiveKindWire;
}

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

  static Future<Map<String, dynamic>?> _readRemote({
    required String lojaId,
    required String docId,
  }) async {
    if (debugRemoteReader != null) {
      return debugRemoteReader!(lojaId, docId);
    }
    final snap = await _db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(docId)
        .get();
    if (!snap.exists) return null;
    return snap.data();
  }

  /// Busca `estoque_produtos` e aplica no [produto].
  /// Com pending: só estrutura de variação (não qty/revision/pending).
  /// Sem pending: qty + metadata + save Hive se em box.
  static Future<bool> hydrateProdutoFromRemoteEstoque({
    required String lojaId,
    required Produto produto,
  }) async {
    final li = lojaId.trim();
    final docId = produto.idFirebase.trim();
    if (li.isEmpty || docId.isEmpty) return false;

    final data = await _readRemote(lojaId: li, docId: docId);
    if (data == null) return false;

    if (hasPendingStockMutation(produto)) {
      return applyRemoteVariationStructureForSaleUi(produto, remote: data);
    }

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

  /// Decisão de UI após hidratação (awaited) — fail closed para variation.
  static Future<SaleVariationRouteResult> resolveSaleVariationRoute({
    required String lojaId,
    required Produto produto,
  }) async {
    final li = lojaId.trim();
    final docId = produto.idFirebase.trim();
    Map<String, dynamic>? remote;
    if (li.isNotEmpty && docId.isNotEmpty) {
      try {
        remote = await _readRemote(lojaId: li, docId: docId);
      } catch (_) {
        remote = null;
      }
    }

    if (remote != null) {
      if (hasPendingStockMutation(produto)) {
        applyRemoteVariationStructureForSaleUi(produto, remote: remote);
      } else {
        applyAuthoritativeRemoteStockToProduto(
          produto,
          remote: remote,
          updateQuantity: true,
        );
        if (produto.isInBox) {
          try {
            await produto.save();
          } catch (_) {}
        }
      }
    }

    final kind = remote != null
        ? effectiveStockKindFromRemote(remote)
        : effectiveStockKindFromProduto(produto);
    final options = produtoSaleVariationPickerOptions(produto);
    final hasReal = produtoHasVariationIdentities(produto) ||
        (remote != null &&
            _hasRealVariationIdentity(
              effectiveCanonicalCellsFromRemote(remote),
            ));

    if (kind == EffectiveStockKind.variation ||
        kind == EffectiveStockKind.grade ||
        hasReal) {
      if (options.isEmpty) {
        return SaleVariationRouteResult(
          decision: SaleVariationRouteDecision.failClosed,
          produto: produto,
          remote: remote,
          options: options,
          effectiveKindWire: kind.wire,
        );
      }
      return SaleVariationRouteResult(
        decision: SaleVariationRouteDecision.openVariationPicker,
        produto: produto,
        remote: remote,
        options: options,
        effectiveKindWire: kind.wire,
      );
    }

    return SaleVariationRouteResult(
      decision: SaleVariationRouteDecision.addAsSimple,
      produto: produto,
      remote: remote,
      options: const [],
      effectiveKindWire: kind.wire,
    );
  }

  static bool _hasRealVariationIdentity(Map<String, int> cells) {
    for (final key in cells.keys) {
      final parts = key.split('|');
      final tam = parts.isNotEmpty ? parts[0] : '';
      final cor = parts.length > 1 ? parts[1] : '';
      final realTam = tam.isNotEmpty && tam != 'sem-tamanho';
      final realCor = cor.isNotEmpty && cor != 'sem-cor';
      if (realTam || realCor) return true;
    }
    return false;
  }

  /// True se o produto (já hidratado) exige picker de variação real.
  /// Célula agregada `sem-tamanho|sem-cor` NÃO conta.
  static bool requiresVariationPicker(Produto p) {
    if (!produtoHasVariationIdentities(p)) return false;
    return produtoSaleVariationPickerOptions(p).isNotEmpty;
  }

  @visibleForTesting
  static void resetForTests() {
    debugFirestoreOverride = null;
    debugRemoteReader = null;
  }
}
