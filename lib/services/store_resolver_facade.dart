// lib/services/store_resolver_facade.dart
// Ponto único de entrada para resolução de loja (facade).
// Delega para StoreResolverService e StoreResolverUnified sem alterar ordem/cache/validações.

import '../core/logger.dart';
import 'store_resolver_service.dart';
import 'store_resolver_unified.dart';

/// Export do tipo de retorno do catálogo para quem usar apenas o facade.
export 'store_resolver_unified.dart' show StoreResolveResult;

/// Facade de resolução de loja: um único ponto de entrada que delega aos serviços existentes.
class StoreResolverFacade {
  StoreResolverFacade._();

  /// Resolve a loja do usuário para o app admin/dashboard.
  /// Delega a [StoreResolverService.resolve()] (Auth → users/{uid} → usuarios/{email} → Hive → slug).
  static Future<String?> resolveForAdminApp() async {
    logD('[STORE_RESOLVE] origem=StoreResolverFacade.resolveForAdminApp antes StoreResolverService.resolve');
    final id = await StoreResolverService.resolve();
    logD('[STORE_RESOLVE] origem=StoreResolverFacade.resolveForAdminApp depois StoreResolverService.resolve valor=${id ?? "null"}');
    return id;
  }

  /// Resolve a loja para o catálogo público a partir do id vindo da URL.
  /// Delega a [StoreResolverUnified.resolve] com contexto publicCatalog.
  /// Não usa usuário logado; valida loja no Firestore, redirect e slug.
  static Future<StoreResolveResult> resolveForPublicCatalog({
    required String? lojaIdFromUrl,
  }) async {
    logD('[STORE-FACADE] resolveForPublicCatalog', tag: 'STORE-FACADE');
    return StoreResolverUnified.resolve(
      context: StoreResolveContext.publicCatalog,
      urlStoreId: lojaIdFromUrl,
    );
  }

  /// Web [main]: após resolver slug → id antes de [CatalogWebRoot], evita 2ª leitura Firestore no catálogo.
  static void seedPublicCatalogResolveFromBootstrap({
    required String urlSlugOrId,
    required String resolvedCanonicalStoreId,
  }) {
    StoreResolverUnified.seedPublicCatalogResolveFromBootstrap(
      urlSlugOrId: urlSlugOrId,
      resolvedCanonicalStoreId: resolvedCanonicalStoreId,
    );
  }

  /// Resolve a loja para o dashboard/admin (preview no app, usuário logado).
  /// Retorna [StoreResolveResult] para manter redirects, canonicalStoreId, errorMessage.
  /// Delega a [StoreResolverUnified.resolve] com contexto adminDashboard.
  static Future<StoreResolveResult> resolveForAdminDashboard({
    required String? lojaIdFromUrl,
  }) async {
    logD('[STORE-FACADE] resolveForAdminDashboard', tag: 'STORE-FACADE');
    return StoreResolverUnified.resolve(
      context: StoreResolveContext.adminDashboard,
      urlStoreId: lojaIdFromUrl,
    );
  }

  /// Resolve a loja para o router (pós-login, bind de sessão).
  /// Delega a [StoreResolverService.resolve()].
  /// [baseUri] disponível para uso futuro (ex.: subdomínio); hoje não altera a resolução.
  static Future<String?> resolveForRouter({required Uri baseUri}) async {
    logD('[STORE-FACADE] resolveForRouter baseUri=$baseUri', tag: 'STORE-FACADE');
    return StoreResolverService.resolve();
  }
}
