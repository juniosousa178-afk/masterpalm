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
  final String? failureReason;
  final String? resolverStage;
  final String? resolverAttempt;
  final Map<String, dynamic>? diagnostics;
  final bool needsRedirect;
  final String? redirectTo;

  StoreResolveResult._({
    required this.success,
    this.storeId,
    this.canonicalStoreId,
    this.errorMessage,
    this.failureReason,
    this.resolverStage,
    this.resolverAttempt,
    this.diagnostics,
    this.needsRedirect = false,
    this.redirectTo,
  });

  factory StoreResolveResult.ok(
    String storeId, {
    String? canonicalId,
    Map<String, dynamic>? diagnostics,
  }) {
    return StoreResolveResult._(
      success: true,
      storeId: storeId,
      canonicalStoreId: canonicalId ?? storeId,
      diagnostics: diagnostics,
    );
  }

  factory StoreResolveResult.redirect(
    String from,
    String to, {
    Map<String, dynamic>? diagnostics,
  }) {
    return StoreResolveResult._(
      success: true,
      storeId: from,
      canonicalStoreId: to,
      needsRedirect: true,
      redirectTo: to,
      diagnostics: diagnostics,
    );
  }

  factory StoreResolveResult.error(
    String message, {
    String? reason,
    String? stage,
    String? attempt,
    Map<String, dynamic>? diagnostics,
  }) {
    return StoreResolveResult._(
      success: false,
      errorMessage: message,
      failureReason: reason,
      resolverStage: stage,
      resolverAttempt: attempt,
      diagnostics: diagnostics,
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
    logD(
        '✅ [STORE-RESOLVER] Cache público (TTL ${_publicCatalogResolveTtl.inSeconds}s): $key');
    return hit.result;
  }

  static void _publicCatalogResolvePutCache(
      String rawId, StoreResolveResult r) {
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
  static Future<StoreResolveResult> _resolvePublicCatalog(
      String? urlStoreId) async {
    final rawId = (urlStoreId ?? '').trim();
    final diagnostics = <String, dynamic>{
      'firestorePath': '',
      'firestoreErrorCode': '',
      'firestoreErrorMessage': '',
      'docExists': false,
      'docId': '',
      'slugField': '',
      'ativo': null,
      'publicado': null,
      'catalogoAtivo': null,
      'status': null,
      'attempts': <Map<String, dynamic>>[],
    };
    CatalogStartupTrace.spanStart(
      'CAT_START.store_resolver_public',
      data: <String, Object?>{'raw_id': rawId},
    );

    if (rawId.isEmpty) {
      logD(
          '❌ [STORE-RESOLVER] URL sem storeId - não pode usar catálogo público');
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{'ok': false, 'mode': 'empty_raw_id'},
      );
      return StoreResolveResult.error(
        'Nenhuma loja especificada na URL. Acesse: /loja/{id-da-loja}',
        reason: 'invalid_slug',
        stage: 'publicCatalog.resolve',
        attempt: 'url_store_id_empty',
        diagnostics: diagnostics,
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
      diagnostics['firestorePath'] = 'lojas/$rawId';
      final lojaDoc = await _db
          .collection('lojas')
          .doc(rawId)
          .get()
          .timeout(const Duration(seconds: timeoutSeconds));
      (diagnostics['attempts'] as List<Map<String, dynamic>>).add({
        'kind': 'doc_get',
        'path': 'lojas/$rawId',
        'exists': lojaDoc.exists,
      });

      if (lojaDoc.exists) {
        final raw = lojaDoc.data();
        final lojaData = asMap(raw);
        diagnostics['docExists'] = true;
        diagnostics['docId'] = rawId;
        diagnostics['slugField'] = (lojaData['slug'] ?? '').toString();
        diagnostics['ativo'] = lojaData['ativo'];
        diagnostics['publicado'] =
            lojaData['publicado'] ?? lojaData['published'];
        diagnostics['catalogoAtivo'] = lojaData['catalogoAtivo'];
        diagnostics['status'] = lojaData['status'];

        final ativo = diagnostics['ativo'];
        final catalogoAtivo = diagnostics['catalogoAtivo'];
        final status = (diagnostics['status'] ?? '').toString().toLowerCase();
        // Alinhar a firestore.rules em `lojas/{lojaId}`: leitura pública só exige que,
        // se existir a chave `published`, o valor não seja false. O campo legado
        // `publicado` sem chave `published` não nega leitura nas rules — não bloquear
        // aqui para evitar catálogo fechado com loja/config acessíveis no Firestore.
        final publishedKeyBlocks = lojaData.containsKey('published') &&
            lojaData['published'] == false;
        final blockByPublishFlag = publishedKeyBlocks ||
            ativo == false ||
            catalogoAtivo == false ||
            status == 'inativo' ||
            status == 'inactive';
        if (blockByPublishFlag) {
          return StoreResolveResult.error(
            'Loja encontrada, mas inativa/não publicada ou catálogo desativado.',
            reason: 'inactive_or_unpublished',
            stage: 'publicCatalog.resolve',
            attempt: 'doc_exact_flags_validation',
            diagnostics: diagnostics,
          );
        }

        // Verificar se há redirect configurado
        final redirectTo = (lojaData['redirectTo'] ?? '').toString().trim();
        if (redirectTo.isNotEmpty && redirectTo != rawId) {
          logD('🔀 [STORE-RESOLVER] Loja $rawId redireciona para $redirectTo');
          final r = StoreResolveResult.redirect(
            rawId,
            redirectTo,
            diagnostics: diagnostics,
          );
          _publicCatalogResolvePutCache(rawId, r);
          return r;
        }

        logD('✅ [STORE-RESOLVER] Loja encontrada: $rawId');
        final ok = StoreResolveResult.ok(rawId, diagnostics: diagnostics);
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
        logD(
            '🔍 [STORE-RESOLVER] Tentando buscar versão lowercase: $normalizedId');

        final normalizedDoc = await _db
            .collection('lojas')
            .doc(normalizedId)
            .get()
            .timeout(const Duration(seconds: 5));
        (diagnostics['attempts'] as List<Map<String, dynamic>>).add({
          'kind': 'doc_get_lowercase',
          'path': 'lojas/$normalizedId',
          'exists': normalizedDoc.exists,
        });
        if (normalizedDoc.exists) {
          logD(
              '🔀 [STORE-RESOLVER] Encontrada versão lowercase, redirecionando');
          final r = StoreResolveResult.redirect(
            rawId,
            normalizedId,
            diagnostics: diagnostics,
          );
          _publicCatalogResolvePutCache(rawId, r);
          CatalogStartupTrace.spanEnd(
            'CAT_START.store_resolver_public',
            data: <String, Object?>{
              'ok': true,
              'mode': 'doc_lowercase_redirect'
            },
          );
          return r;
        }
      }

      // Tentar buscar por slug
      diagnostics['firestorePath'] = 'lojas.where(slug==$rawId)';
      final slugResult = await _findBySlug(rawId, diagnostics);
      if (slugResult != null) {
        logD('🔀 [STORE-RESOLVER] Encontrado por slug: $slugResult');
        final r = StoreResolveResult.redirect(
          rawId,
          slugResult,
          diagnostics: diagnostics,
        );
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
        reason: 'not_found',
        stage: 'publicCatalog.resolve',
        attempt: 'lojas/$rawId + lojas.where(slug==$rawId)',
        diagnostics: diagnostics,
      );
    } on TimeoutException catch (_) {
      logW(
          '⚠️ [STORE-RESOLVER] Timeout ao buscar loja. Usando id da URL: $rawId');
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{'ok': true, 'mode': 'timeout_fallback_url_id'},
      );
      return StoreResolveResult.ok(rawId, diagnostics: diagnostics);
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
        logW(
            '⚠️ [STORE-RESOLVER] Erro de rede/Firestore. Usando id da URL: $rawId');
        CatalogStartupTrace.spanEnd(
          'CAT_START.store_resolver_public',
          data: <String, Object?>{
            'ok': true,
            'mode': 'network_fallback_url_id'
          },
        );
        return StoreResolveResult.ok(rawId, diagnostics: diagnostics);
      }
      final em = e.toString().toLowerCase();
      final isPermissionDenied = em.contains('permission-denied') ||
          em.contains('missing or insufficient permissions');
      final isAppCheck = em.contains('appcheck') ||
          em.contains('app check') ||
          em.contains('recaptcha');
      logD('❌ [STORE-RESOLVER] Erro ao buscar loja (type=${e.runtimeType})');
      CatalogStartupTrace.spanEnd(
        'CAT_START.store_resolver_public',
        data: <String, Object?>{
          'ok': false,
          'error_type': e.runtimeType.toString()
        },
      );
      diagnostics['firestoreErrorMessage'] = e.toString();
      if (em.contains('permission-denied')) {
        diagnostics['firestoreErrorCode'] = 'permission-denied';
      } else if (em.contains('appcheck') || em.contains('app check')) {
        diagnostics['firestoreErrorCode'] = 'appcheck';
      }
      return StoreResolveResult.error(
        'Erro ao carregar loja: $e',
        reason: isPermissionDenied
            ? 'permission_denied'
            : (isAppCheck ? 'appcheck_blocked' : 'exception'),
        stage: 'publicCatalog.resolve',
        attempt: 'lojas/$rawId + lojas.where(slug==$rawId)',
        diagnostics: diagnostics,
      );
    }
  }

  // ============================================================
  // RESOLUÇÃO ADMIN (DASHBOARD)
  // ============================================================

  /// Resolve loja para dashboard/admin
  /// REGRA: SEMPRE usa loja do usuário logado
  static Future<StoreResolveResult> _resolveAdminDashboard() async {
    try {
      logD(
          '[STORE_RESOLVE] origem=StoreResolverUnified._resolveAdminDashboard antes StoreResolverService.resolve');
      final storeId = await StoreResolverService.resolve();
      logD(
          '[STORE_RESOLVE] origem=StoreResolverUnified._resolveAdminDashboard depois StoreResolverService.resolve valor=${storeId ?? "null"}');

      if (storeId == null || storeId.trim().isEmpty) {
        logD('❌ [STORE-RESOLVER] Usuário sem loja configurada');
        return StoreResolveResult.error(
          'Nenhuma loja configurada para este usuário.',
        );
      }

      logD('✅ [STORE-RESOLVER] Loja do usuário: $storeId');
      return StoreResolveResult.ok(storeId);
    } catch (e) {
      logD(
          '❌ [STORE-RESOLVER] Erro ao resolver loja do usuário (type=${e.runtimeType})');
      return StoreResolveResult.error('Erro ao carregar sua loja: $e');
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================

  /// Busca loja por slug
  static Future<String?> _findBySlug(
    String slug,
    Map<String, dynamic>? diagnostics,
  ) async {
    try {
      final normalizedSlug = slug.toLowerCase().trim();

      final query = await _db
          .collection('lojas')
          .where('slug', isEqualTo: normalizedSlug)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      final attempts = diagnostics?['attempts'];
      if (attempts is List<Map<String, dynamic>>) {
        attempts.add({
          'kind': 'slug_query',
          'path': 'lojas.where(slug==$normalizedSlug)',
          'count': query.docs.length,
        });
      }

      if (query.docs.isNotEmpty) {
        final data = asMap(query.docs.first.data());
        diagnostics?['docExists'] = true;
        diagnostics?['docId'] = query.docs.first.id;
        diagnostics?['slugField'] = (data['slug'] ?? '').toString();
        diagnostics?['ativo'] = data['ativo'];
        diagnostics?['publicado'] = data['publicado'] ?? data['published'];
        diagnostics?['catalogoAtivo'] = data['catalogoAtivo'];
        diagnostics?['status'] = data['status'];
        return query.docs.first.id;
      }
    } catch (e) {
      diagnostics?['firestoreErrorMessage'] = e.toString();
      logW(
          '⚠️ [STORE-RESOLVER] Erro ao buscar por slug (type=${e.runtimeType})');
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
      logW(
          '⚠️ [STORE-RESOLVER] Erro ao normalizar storeId (type=${e.runtimeType})');
    }
  }
}
