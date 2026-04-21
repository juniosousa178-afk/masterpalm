// lib/services/store_resolver_unified.dart
// =============================================================================
// FONTE ÚNICA DE RESOLUÇÃO DE LOJA - Multi-Tenant Seguro
// =============================================================================
// Regras:
// 1. PÁGINA PÚBLICA: SEMPRE por storeId da URL (NUNCA por usuário logado)
// 2. PÁGINA ADMIN/DASHBOARD: SEMPRE por loja do usuário logado
// 3. Case-sensitivity: Normalizar para lowercase e criar redirects
// =============================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:hive/hive.dart';

import '../core/logger.dart';
import '../core/safe_cast.dart';
import '../debug/catalog_startup_trace.dart';
import '../utils/last_route_observer.dart';
import 'loja_id_service.dart';
import 'store_resolver_service.dart';
import 'store_context.dart';

class _PublicCatalogResolveCacheEntry {
  final StoreResolveResult result;
  final DateTime cachedAt;

  _PublicCatalogResolveCacheEntry(this.result, this.cachedAt);
}

/// Contexto de resolução de loja
enum StoreResolveContext {
  /// Página pública (catálogo do cliente) - usa storeId da URL
  publicCatalog,

  /// Dashboard/Admin - usa loja do usuário logado
  adminDashboard,
}

/// Resultado da resolução de loja
class StoreResolveResult {
  final bool success;
  final String? storeId;
  final String? canonicalStoreId; // ID canônico (após redirect se houver)
  final String? errorMessage;
  final bool needsRedirect;
  final String? redirectTo;

  StoreResolveResult._({
    required this.success,
    this.storeId,
    this.canonicalStoreId,
    this.errorMessage,
    this.needsRedirect = false,
    this.redirectTo,
  });

  factory StoreResolveResult.ok(String storeId, {String? canonicalId}) {
    return StoreResolveResult._(
      success: true,
      storeId: storeId,
      canonicalStoreId: canonicalId ?? storeId,
    );
  }

  factory StoreResolveResult.redirect(String from, String to) {
    return StoreResolveResult._(
      success: true,
      storeId: from,
      canonicalStoreId: to,
      needsRedirect: true,
      redirectTo: to,
    );
  }

  factory StoreResolveResult.error(String message) {
    return StoreResolveResult._(
      success: false,
      errorMessage: message,
    );
  }
}

/// Serviço unificado de resolução de loja
class StoreResolverUnified {
  StoreResolverUnified._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Evita 2ª ida ao Firestore logo após o [main] resolver slug → id (mesma aba / recarregar).
  static final Map<String, _PublicCatalogResolveCacheEntry>
      _publicCatalogResolveCache = {};
  static const Duration _publicCatalogResolveTtl = Duration(minutes: 2);

  static StoreResolveResult? _publicCatalogResolveFromCache(String rawId) {
    final key = rawId.toLowerCase();
    final hit = _publicCatalogResolveCache[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.cachedAt) > _publicCatalogResolveTtl) {
      _publicCatalogResolveCache.remove(key);
      return null;
    }
    logD('✅ [STORE-RESOLVER] Cache público (TTL ${_publicCatalogResolveTtl.inSeconds}s): $key');
    return hit.result;
  }

  static void _publicCatalogResolvePutCache(String rawId, StoreResolveResult r) {
    if (!r.success) return;
    _publicCatalogResolveCache[rawId.toLowerCase()] =
        _PublicCatalogResolveCacheEntry(r, DateTime.now());
  }

  /// [main] Web: após [slug/query → id canônico], alimenta o cache para [PublicCatalogScreen]
  /// não repetir `lojas/{id}.get()` na primeira pintura.
  static void seedPublicCatalogResolveFromBootstrap({
    required String urlSlugOrId,
    required String resolvedCanonicalStoreId,
  }) {
    final can = resolvedCanonicalStoreId.trim();
    final raw = urlSlugOrId.trim();
    if (can.isEmpty || raw.isEmpty) return;
    if (can.toLowerCase() == raw.toLowerCase()) {
      _publicCatalogResolvePutCache(raw, StoreResolveResult.ok(can));
      return;
    }
    _publicCatalogResolvePutCache(
      raw,
      StoreResolveResult.redirect(raw, can),
    );
    _publicCatalogResolvePutCache(can, StoreResolveResult.ok(can));
  }

  // ============================================================
  // RESOLUÇÃO PRINCIPAL
  // ============================================================

  /// Resolve a loja baseado no contexto
  ///
  /// [context] - Contexto de uso (público ou admin)
  /// [urlStoreId] - StoreId vindo da URL (apenas para contexto público)
  static Future<StoreResolveResult> resolve({
    required StoreResolveContext context,
    String? urlStoreId,
  }) async {
    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    logD('🔒 [STORE-RESOLVER-UNIFIED] Resolvendo loja');
    logD('   Contexto: ${context.name}');
    logD('   URL storeId: $urlStoreId');
    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    switch (context) {
      case StoreResolveContext.publicCatalog:
        return _resolvePublicCatalog(urlStoreId);

      case StoreResolveContext.adminDashboard:
        return _resolveAdminDashboard();
    }
  }

  // ============================================================
  // RESOLUÇÃO PÚBLICA (CATÁLOGO)
  // ============================================================

  /// Resolve loja para catálogo público
  /// REGRA: SEMPRE usa storeId da URL, NUNCA do usuário logado
  static Future<StoreResolveResult> _resolvePublicCatalog(String? urlStoreId) async {
    final rawId = (urlStoreId ?? '').trim();
    CatalogStartupTrace.spanStart(
      'CAT_START.store_resolver_public',
      data: <String, Object?>{'raw_id': rawId},
    );

    if (rawId.isEmpty) {
      logD('❌ [STORE-RESOLVER] URL sem storeId - não pode usar catálogo público');
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{'ok': false, 'mode': 'empty_raw_id'},
      );
      return StoreResolveResult.error(
        'Nenhuma loja especificada na URL. Acesse: /loja/{id-da-loja}',
      );
    }

    final cached = _publicCatalogResolveFromCache(rawId);
    if (cached != null) {
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{'ok': true, 'mode': 'cache_hit'},
      );
      return cached;
    }

    // Verificar se a loja existe no Firestore (timeout curto na web para não travar)
    try {
      const timeoutSeconds = 5;
      final lojaDoc = await _db
          .collection('lojas')
          .doc(rawId)
          .get()
          .timeout(const Duration(seconds: timeoutSeconds));

      if (lojaDoc.exists) {
        final raw = lojaDoc.data();
        final lojaData = asMap(raw);

        // Verificar se há redirect configurado
        final redirectTo = (lojaData['redirectTo'] ?? '').toString().trim();
        if (redirectTo.isNotEmpty && redirectTo != rawId) {
          logD('🔀 [STORE-RESOLVER] Loja $rawId redireciona para $redirectTo');
          final r = StoreResolveResult.redirect(rawId, redirectTo);
          _publicCatalogResolvePutCache(rawId, r);
          return r;
        }

        logD('✅ [STORE-RESOLVER] Loja encontrada: $rawId');
        final ok = StoreResolveResult.ok(rawId);
        _publicCatalogResolvePutCache(rawId, ok);
        CatalogStartupTrace.spanEnd(
          'CAT_START.store_resolver_public',
          data: <String, Object?>{'ok': true, 'mode': 'doc_exact'},
        );
        return ok;
      }

      // Loja não existe com esse ID exato
      // Tentar buscar por case-insensitive (normalizado para lowercase)
      final normalizedId = rawId.toLowerCase();
      if (normalizedId != rawId) {
        logD('🔍 [STORE-RESOLVER] Tentando buscar versão lowercase: $normalizedId');

        final normalizedDoc = await _db
            .collection('lojas')
            .doc(normalizedId)
            .get()
            .timeout(const Duration(seconds: 5));
        if (normalizedDoc.exists) {
          logD('🔀 [STORE-RESOLVER] Encontrada versão lowercase, redirecionando');
          final r = StoreResolveResult.redirect(rawId, normalizedId);
          _publicCatalogResolvePutCache(rawId, r);
          CatalogStartupTrace.spanEnd(
            'CAT_START.store_resolver_public',
            data: <String, Object?>{'ok': true, 'mode': 'doc_lowercase_redirect'},
          );
          return r;
        }
      }

      // Tentar buscar por slug
      final slugResult = await _findBySlug(rawId);
      if (slugResult != null) {
        logD('🔀 [STORE-RESOLVER] Encontrado por slug: $slugResult');
        final r = StoreResolveResult.redirect(rawId, slugResult);
        _publicCatalogResolvePutCache(rawId, r);
        CatalogStartupTrace.spanEnd(
          'CAT_START.store_resolver_public',
          data: <String, Object?>{'ok': true, 'mode': 'slug_redirect'},
        );
        return r;
      }

      logD('❌ [STORE-RESOLVER] Loja não encontrada: $rawId');
      return StoreResolveResult.error(
        'Loja "$rawId" não encontrada. Verifique o link.',
      );
    } on TimeoutException catch (_) {
      logW('⚠️ [STORE-RESOLVER] Timeout ao buscar loja. Usando id da URL: $rawId');
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{'ok': true, 'mode': 'timeout_fallback_url_id'},
      );
      return StoreResolveResult.ok(rawId);
    } catch (e) {
      // Qualquer erro (rede, Firestore indisponível, etc.): fallback com id da URL
      // para o catálogo tentar abrir; se o id for inválido, a tela ficará vazia
      final msg = e.toString().toLowerCase();
      final isNetworkOrTimeout = msg.contains('timeout') ||
          msg.contains('not completed') ||
          msg.contains('connection') ||
          msg.contains('backend') ||
          msg.contains('unavailable') ||
          msg.contains('offline');
      if (isNetworkOrTimeout) {
        logW('⚠️ [STORE-RESOLVER] Erro de rede/Firestore. Usando id da URL: $rawId');
        CatalogStartupTrace.spanEnd(
          'CAT_START.store_resolver_public',
          data: <String, Object?>{'ok': true, 'mode': 'network_fallback_url_id'},
        );
        return StoreResolveResult.ok(rawId);
      }
      logD('❌ [STORE-RESOLVER] Erro ao buscar loja (type=${e.runtimeType})');
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{'ok': false, 'error_type': e.runtimeType.toString()},
      );
      return StoreResolveResult.error('Erro ao carregar loja: $e');
    }
  }

  // ============================================================
  // RESOLUÇÃO ADMIN (DASHBOARD)
  // ============================================================

  /// Resolve loja para dashboard/admin
  /// REGRA: SEMPRE usa loja do usuário logado
  static Future<StoreResolveResult> _resolveAdminDashboard() async {
    try {
      logD('[STORE_RESOLVE] origem=StoreResolverUnified._resolveAdminDashboard antes StoreResolverService.resolve');
      final storeId = await StoreResolverService.resolve();
      logD('[STORE_RESOLVE] origem=StoreResolverUnified._resolveAdminDashboard depois StoreResolverService.resolve valor=${storeId ?? "null"}');

      if (storeId == null || storeId.trim().isEmpty) {
        logD('❌ [STORE-RESOLVER] Usuário sem loja configurada');
        return StoreResolveResult.error(
          'Nenhuma loja configurada para este usuário.',
        );
      }

      logD('✅ [STORE-RESOLVER] Loja do usuário: $storeId');
      return StoreResolveResult.ok(storeId);
    } catch (e) {
      logD('❌ [STORE-RESOLVER] Erro ao resolver loja do usuário (type=${e.runtimeType})');
      return StoreResolveResult.error('Erro ao carregar sua loja: $e');
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Busca loja por slug
  static Future<String?> _findBySlug(String slug) async {
    try {
      final normalizedSlug = slug.toLowerCase().trim();

      final query = await _db
          .collection('lojas')
          .where('slug', isEqualTo: normalizedSlug)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (query.docs.isNotEmpty) {
        return query.docs.first.id;
      }
    } catch (e) {
      logW('⚠️ [STORE-RESOLVER] Erro ao buscar por slug (type=${e.runtimeType})');
    }
    return null;
  }

  // ============================================================
  // LIMPEZA COMPLETA DE CACHE (PARA LOGOUT)
  // ============================================================

  /// Limpa TODOS os caches de loja
  /// DEVE ser chamado no logout para evitar mistura de dados entre usuários
  static Future<void> clearAllCaches() async {
    logD('🧹 [STORE-RESOLVER] Limpando TODOS os caches de loja...');

    _publicCatalogResolveCache.clear();

    // 1. Limpar StoreResolverService
    StoreResolverService.invalidate();
    await StoreResolverService.clear();

    // 2. Limpar StoreContext
    StoreContext.invalidate();
    await StoreContext.clear();

    // 3. Limpar Hive boxes
    try {
      final sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      await sessao.delete('store_id');
      await sessao.delete('usuario_logado');
      await sessao.delete('tipo_usuario');
      await sessao.delete('is_root');
    } catch (e) {
      logW('⚠️ [STORE-RESOLVER] Erro ao limpar sessao (type=${e.runtimeType})');
    }

    try {
      final config = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      await config.delete('store_id');
      await config.delete('store_slug');
      await config.delete('loja_slug');
      await config.delete('last_loja_id');
    } catch (e) {
      logW('⚠️ [STORE-RESOLVER] Erro ao limpar config (type=${e.runtimeType})');
    }

    await LojaIdService.clear();
    await LastRouteObserver.clearLastRoute();

    logD('✅ [STORE-RESOLVER] Todos os caches limpos');
  }

  // ============================================================
  // NORMALIZAÇÃO DE STORE ID
  // ============================================================

  /// Verifica se um storeId precisa de normalização e cria redirect se necessário
  static Future<void> ensureNormalizedStoreId(String storeId) async {
    final normalized = storeId.toLowerCase();

    if (normalized == storeId) {
      // Já está normalizado
      return;
    }

    try {
      // Verificar se o doc com case original existe
      final originalDoc = await _db.collection('lojas').doc(storeId).get();
      if (!originalDoc.exists) return;

      // Verificar se já existe doc normalizado
      final normalizedDoc = await _db.collection('lojas').doc(normalized).get();

      if (!normalizedDoc.exists) {
        // Criar doc normalizado com dados do original
        final raw = originalDoc.data();
        final data = asMap(raw);
        data['lojaId'] = normalized;
        data['id'] = normalized;
        data['slug'] = normalized;
        data['migratedFrom'] = storeId;
        data['migratedAt'] = FieldValue.serverTimestamp();

        await _db.collection('lojas').doc(normalized).set(data);
        logD('✅ [STORE-RESOLVER] Criado doc normalizado: $normalized');
      }

      // Configurar redirect no doc original
      await _db.collection('lojas').doc(storeId).update({
        'redirectTo': normalized,
      });
      logD('✅ [STORE-RESOLVER] Redirect configurado: $storeId → $normalized');
    } catch (e) {
      logW('⚠️ [STORE-RESOLVER] Erro ao normalizar storeId (type=${e.runtimeType})');
    }
  }
}
