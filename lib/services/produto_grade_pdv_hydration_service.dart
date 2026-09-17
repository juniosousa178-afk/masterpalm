// Hidratação pontual de produto para decisão de grade/variação no PDV.
// Reutiliza ProdutosFirestoreService.ensureEstoqueProdutoDocsInHive (sem segundo modelo).

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

import '../core/produto_grade_pdv_hydration.dart';
import '../models/produto.dart';
import 'produtos_firestore_service.dart';

typedef GradePdvOnlineCheck = Future<bool> Function();
typedef GradePdvRemoteHydrate =
    Future<void> Function({
      required String lojaId,
      required Box<Produto> produtosBox,
      required String productId,
    });

/// Serviço de hidratação pontual por productId (dedupe + sessão autoritativa).
class ProdutoGradePdvHydrationService {
  ProdutoGradePdvHydrationService._();

  static final Map<String, Future<GradePdvHydrationResult>> _inflight = {};
  static final Set<String> _authoritativeKeys = {};

  /// Hooks de teste (não usar em produção).
  static GradePdvOnlineCheck? debugOnlineCheckOverride;
  static GradePdvRemoteHydrate? debugRemoteHydrateOverride;

  static void debugReset() {
    _inflight.clear();
    _authoritativeKeys.clear();
    debugOnlineCheckOverride = null;
    debugRemoteHydrateOverride = null;
  }

  static bool isSessionAuthoritative({
    required String lojaId,
    required String productId,
  }) {
    return _authoritativeKeys.contains(
      gradePdvHydrationKey(lojaId, productId),
    );
  }

  static void markSessionAuthoritative({
    required String lojaId,
    required String productId,
  }) {
    final id = productId.trim();
    final lid = lojaId.trim();
    if (lid.isEmpty || id.isEmpty) return;
    _authoritativeKeys.add(gradePdvHydrationKey(lid, id));
  }

  static Produto? findProdutoInBox({
    required Box<Produto> produtosBox,
    required String lojaId,
    required String productId,
  }) {
    final lid = lojaId.trim();
    final id = productId.trim();
    if (lid.isEmpty || id.isEmpty) return null;
    for (final p in produtosBox.values) {
      if (p.lojaId != lid) continue;
      if (p.idFirebase.trim() == id || p.slug.trim() == id) return p;
    }
    return null;
  }

  static Future<bool> _defaultIsOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return true;
      return !(results.length == 1 && results.first == ConnectivityResult.none);
    } catch (_) {
      // Em dúvida, tenta remoto (falha vira offlinePartial).
      return true;
    }
  }

  static Future<void> _defaultRemoteHydrate({
    required String lojaId,
    required Box<Produto> produtosBox,
    required String productId,
  }) {
    return ProdutosFirestoreService.ensureEstoqueProdutoDocsInHive(
      lojaId: lojaId,
      produtosBox: produtosBox,
      firebaseDocIds: [productId],
      forceRefreshFromRemoto: true,
    );
  }

  /// Hidrata o produto alvo por ID. Deduplica fetches concorrentes da mesma chave.
  static Future<GradePdvHydrationResult> hydrateByProductId({
    required String lojaId,
    required String productId,
    required Box<Produto> produtosBox,
    Produto? seed,
  }) {
    final lid = lojaId.trim();
    final id = productId.trim();
    final key = gradePdvHydrationKey(lid, id);
    if (lid.isEmpty || id.isEmpty) {
      return Future.value(
        GradePdvHydrationResult(
          lojaId: lid,
          productId: id,
          readiness: GradePdvReadiness.offlinePartial,
          produto: seed,
          errorMessage: 'Produto sem identificador para hidratação',
        ),
      );
    }

    final existing = _inflight[key];
    if (existing != null) return existing;

    final future = _hydrateOnce(
      lojaId: lid,
      productId: id,
      produtosBox: produtosBox,
      seed: seed,
    );
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) {
        _inflight.remove(key);
      }
    });
    return future;
  }

  static Future<GradePdvHydrationResult> _hydrateOnce({
    required String lojaId,
    required String productId,
    required Box<Produto> produtosBox,
    Produto? seed,
  }) async {
    final localBefore =
        findProdutoInBox(
          produtosBox: produtosBox,
          lojaId: lojaId,
          productId: productId,
        ) ??
        seed;

    final onlineCheck = debugOnlineCheckOverride ?? _defaultIsOnline;
    final online = await onlineCheck();

    if (!online) {
      if (localBefore != null && gradePdvHasLocalVariationSignal(localBefore)) {
        // Cache completo offline: pode renderizar grade.
        return GradePdvHydrationResult(
          lojaId: lojaId,
          productId: productId,
          readiness: GradePdvReadiness.readyWithVariation,
          produto: localBefore,
        );
      }
      // Offline + parcial: NÃO marcar autoritativo; NÃO cair em SIMPLE.
      return GradePdvHydrationResult(
        lojaId: lojaId,
        productId: productId,
        readiness: GradePdvReadiness.offlinePartial,
        produto: localBefore,
        errorMessage: 'Não foi possível carregar as variações',
      );
    }

    try {
      final remote = debugRemoteHydrateOverride ?? _defaultRemoteHydrate;
      await remote(
        lojaId: lojaId,
        produtosBox: produtosBox,
        productId: productId,
      );

      final updated =
          findProdutoInBox(
            produtosBox: produtosBox,
            lojaId: lojaId,
            productId: productId,
          ) ??
          localBefore;

      markSessionAuthoritative(lojaId: lojaId, productId: productId);

      if (updated != null && gradePdvHasLocalVariationSignal(updated)) {
        return GradePdvHydrationResult(
          lojaId: lojaId,
          productId: productId,
          readiness: GradePdvReadiness.readyWithVariation,
          produto: updated,
        );
      }

      return GradePdvHydrationResult(
        lojaId: lojaId,
        productId: productId,
        readiness: GradePdvReadiness.readyWithoutVariation,
        produto: updated,
      );
    } catch (e) {
      if (localBefore != null && gradePdvHasLocalVariationSignal(localBefore)) {
        return GradePdvHydrationResult(
          lojaId: lojaId,
          productId: productId,
          readiness: GradePdvReadiness.readyWithVariation,
          produto: localBefore,
        );
      }
      return GradePdvHydrationResult(
        lojaId: lojaId,
        productId: productId,
        readiness: GradePdvReadiness.offlinePartial,
        produto: localBefore,
        errorMessage: 'Não foi possível carregar as variações',
      );
    }
  }

  /// Resolve readiness para abrir sheet vs SIMPLE vs loading/erro.
  /// Se já há sinal local de variação, retorna imediatamente (sheet abre;
  /// a sheet pode rehidratar ao vivo). Caso contrário hidrata antes de SIMPLE.
  static Future<GradePdvHydrationResult> resolveForPdvSelection({
    required String lojaId,
    required Produto seed,
    required Box<Produto> produtosBox,
  }) async {
    final productId = gradePdvProductId(seed);
    if (productId == null) {
      // Sem ID: só permite SIMPLE se não houver sinal de variação (legado).
      if (gradePdvHasLocalVariationSignal(seed)) {
        return GradePdvHydrationResult(
          lojaId: lojaId,
          productId: '',
          readiness: GradePdvReadiness.readyWithVariation,
          produto: seed,
        );
      }
      return GradePdvHydrationResult(
        lojaId: lojaId,
        productId: '',
        readiness: GradePdvReadiness.readyWithoutVariation,
        produto: seed,
      );
    }

    if (gradePdvHasLocalVariationSignal(seed)) {
      return GradePdvHydrationResult(
        lojaId: lojaId,
        productId: productId,
        readiness: GradePdvReadiness.readyWithVariation,
        produto: seed,
      );
    }

    if (isSessionAuthoritative(lojaId: lojaId, productId: productId)) {
      final live =
          findProdutoInBox(
            produtosBox: produtosBox,
            lojaId: lojaId,
            productId: productId,
          ) ??
          seed;
      if (gradePdvHasLocalVariationSignal(live)) {
        return GradePdvHydrationResult(
          lojaId: lojaId,
          productId: productId,
          readiness: GradePdvReadiness.readyWithVariation,
          produto: live,
        );
      }
      return GradePdvHydrationResult(
        lojaId: lojaId,
        productId: productId,
        readiness: GradePdvReadiness.readyWithoutVariation,
        produto: live,
      );
    }

    return hydrateByProductId(
      lojaId: lojaId,
      productId: productId,
      produtosBox: produtosBox,
      seed: seed,
    );
  }
}
