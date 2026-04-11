// lib/services/loja_id_service.dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/loja_id_adapter.dart';
import '../core/logger.dart';
import '../services/public_store_link_helper.dart';
import '../services/store_resolver_facade.dart';
import 'store_context.dart';

class LojaIdService extends ChangeNotifier {
  String? _lojaId;

  static LojaIdService? _instance;

  LojaIdService() {
    _instance = this;
  }

  String? get lojaId => _lojaId;

  /// Compat: usado no código legado
  String? getLoja() => _lojaId;

  // ============================================================
  // ✅ BOOTSTRAP: carrega a loja ativa (chame no start do app)
  // ============================================================
  Future<void> bootstrap() async {
    final id = await LojaIdService.get();
    if (id != null && id.trim().isNotEmpty) {
      if (_lojaId != id) {
        _lojaId = id;
        notifyListeners();
      }
    }
  }

  // ============================================================
  // ✅ SET (instância): altera + persiste (Hive + StoreContext)
  // ============================================================
  Future<void> setLoja(String? novoId) async {
    final id = (novoId ?? '').trim();

    if (id.isEmpty) {
      await LojaIdService.clear();
      if (_lojaId != null) {
        _lojaId = null;
        notifyListeners();
      }
      return;
    }

    if (_lojaId == id) return;

    _lojaId = id;
    notifyListeners();

    // persiste para todo o app ficar alinhado
    await LojaIdService.set(id);
  }

  // ============================================================
  // ✅ FONTE ÚNICA: resolve loja ativa com prioridade correta
  // ============================================================
  static Future<String?> get() async {
    try {
      logD('[LOJAID] origem=LojaIdService.get antes StoreResolverFacade.resolveForAdminApp');
      final id = await StoreResolverFacade.resolveForAdminApp();
      logD('[LOJAID] origem=LojaIdService.get depois StoreResolverFacade.resolveForAdminApp valor=${id ?? "null"}');
      final trimmed = id?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
      logW('[LOJAID] origem=LojaIdService.get retorno null motivo=StoreResolver retornou vazio');
    } catch (e) {
      debugPrint(
        '[LOJAID] origem=LojaIdService.get erro StoreResolverFacade.resolveForAdminApp type=${e.runtimeType}',
      );
    }

    // 2) Hive fallback: só usar se currentUser coincide com usuario_logado (evita contaminação)
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null) {
        logW(
          '[LOJA_ID] resolve_failed_no_safe_context motivo=currentUser_null',
        );
        return null;
      }

      final Box sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      final cachedUserEmail =
          (sessao.get('usuario_logado_email') ?? '').toString().trim().toLowerCase();
      final cachedUserLegacy =
          (sessao.get('usuario_logado') ?? '').toString().trim().toLowerCase();
      final cachedUser = cachedUserEmail.isNotEmpty ? cachedUserEmail : cachedUserLegacy;
      final currentEmail = (current.email ?? '').trim().toLowerCase();
      if (cachedUser.isEmpty || currentEmail != cachedUser) {
        logW('[LOJAID] origem=LojaIdService.get fallback sessao rejeitado motivo=principal mismatch currentEmail=$currentEmail cachedUser=$cachedUser');
        return null;
      }

      final rawId = normalizeFromBox(sessao);
      if (rawId != null && rawId.isNotEmpty) return rawId;
    } catch (e) {
      debugPrint(
        '[LOJA_ID] Erro ao ler loja da box "sessao" (get) (type=${e.runtimeType})',
      );
    }

    // 3) Hive config: mesma validação de usuário
    try {
      final current = FirebaseAuth.instance.currentUser;
      if (current == null) return null;

      final Box sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      final cachedUserEmail =
          (sessao.get('usuario_logado_email') ?? '').toString().trim().toLowerCase();
      final cachedUserLegacy =
          (sessao.get('usuario_logado') ?? '').toString().trim().toLowerCase();
      final cachedUser = cachedUserEmail.isNotEmpty ? cachedUserEmail : cachedUserLegacy;
      final currentEmail = (current.email ?? '').trim().toLowerCase();
      if (cachedUser.isEmpty || currentEmail != cachedUser) {
        logW('[LOJAID] origem=LojaIdService.get fallback config rejeitado motivo=principal mismatch currentEmail=$currentEmail cachedUser=$cachedUser');
        return null;
      }

      final Box cfg = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      final rawId = normalizeFromBox(cfg);
      if (rawId != null && rawId.isNotEmpty) return rawId;
    } catch (e) {
      debugPrint(
        '[LOJA_ID] Erro ao ler loja da box "config" (get) (type=${e.runtimeType})',
      );
    }

    logW('[LOJAID] origem=LojaIdService.get retorno null motivo=nenhuma fonte valida');
    return null;
  }

  /// Resolve loja com timeout; em caso de falha, tenta Hive sessao (offline).
  /// Nunca retorna 'padrao' nem placeholder (minha-loja). Retorna null se não conseguir resolver.
  /// Web: usa timeout maior e mais retries (Auth/Firestore podem demorar).
  static Future<String?> getWithTimeout({
    Duration? timeout,
  }) async {
    // Web: Auth pode demorar a restaurar sessão; usar timeout maior para evitar "Não foi possível carregar a loja"
    final effectiveTimeout = timeout != null
        ? (kIsWeb && timeout.inSeconds < 30 ? const Duration(seconds: 30) : timeout)
        : (kIsWeb ? const Duration(seconds: 30) : const Duration(seconds: 10));
    const retryTimeout = kIsWeb ? Duration(seconds: 20) : Duration(seconds: 5);
    logD(
      '[LOJA_ID] resolve_start getWithTimeout timeout=${effectiveTimeout.inSeconds}s web=$kIsWeb',
    );

    // ⚠️ NÃO usar Hive como fast path: no Web, IndexedDB é compartilhado e pode ter
    // store_id de outro usuário (contaminação entre juniosousa178 e trindadejunio70).

    try {
      logD('[LOJAID] origem=LojaIdService.getWithTimeout antes StoreResolverFacade.resolveForAdminApp tentativa=1');
      final id = await StoreResolverFacade.resolveForAdminApp()
          .timeout(effectiveTimeout, onTimeout: () => null);
      logD('[LOJAID] origem=LojaIdService.getWithTimeout depois StoreResolverFacade.resolveForAdminApp tentativa=1 valor=${id ?? "null"}');
      final trimmed = id?.trim() ?? '';
      if (trimmed.isNotEmpty && isValidForPublicLink(trimmed)) {
        logD('[LOJA_ID] resolve_success fonte=StoreResolver tentativa=1');
        return trimmed;
      }
      // Retry quando retorna null/vazio (ex: Auth ainda não pronto no Web ao voltar)
      logD('[STORE-RESOLVE] Primeira tentativa retornou vazio, aguardando 2s para retry...');
      await Future<void>.delayed(const Duration(seconds: 2));
      logD('[LOJAID] origem=LojaIdService.getWithTimeout antes StoreResolverFacade.resolveForAdminApp tentativa=2');
      final idRetry = await StoreResolverFacade.resolveForAdminApp()
          .timeout(effectiveTimeout, onTimeout: () => null);
      logD('[LOJAID] origem=LojaIdService.getWithTimeout depois StoreResolverFacade.resolveForAdminApp tentativa=2 valor=${idRetry ?? "null"}');
      final trimmedRetry = idRetry?.trim() ?? '';
      if (trimmedRetry.isNotEmpty && isValidForPublicLink(trimmedRetry)) {
        logD('[LOJA_ID] resolve_success fonte=StoreResolver tentativa=2');
        return trimmedRetry;
      }
    } on TimeoutException {
      logW('[LOJA_ID] resolve_timeout tentando_retry_apos_timeout');
      // Retry: no Web o Auth pode ter ficado pronto após o timeout
      try {
        logD('[LOJA_ID] resolve_start tentativa=timeout-retry');
        final id = await StoreResolverFacade.resolveForAdminApp()
            .timeout(retryTimeout, onTimeout: () => null);
        logD('[LOJA_ID] resolve_after_timeout valor=${id != null && id.isNotEmpty ? "ok" : "null"}');
        final trimmed = id?.trim() ?? '';
        if (trimmed.isNotEmpty && isValidForPublicLink(trimmed)) {
          logD('[LOJA_ID] resolve_success fonte=StoreResolver tentativa=timeout-retry');
          return trimmed;
        }
      } catch (e, st) {
        logE('[LOJA_ID] resolve_timeout_retry_failed', error: e, st: st);
      }
    } catch (e) {
      logE('[STORE_SCREEN] Erro ao resolver loja (type=${e.runtimeType})', error: e);
    }

    // ⚠️ NÃO usar Hive sessao/config como fallback: store_id pode ser de outro usuário
    // (mesmo navegador, troca de conta). Só StoreResolver (Firestore) é confiável.

    // Web: última tentativa após breve espera (Auth pode estar restaurando)
    if (kIsWeb) {
      logD('[STORE_SCREEN] Web: última tentativa após 3s...');
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final id = await get();
        final trimmed = id?.trim() ?? '';
        if (trimmed.isNotEmpty && isValidForPublicLink(trimmed)) {
          logD('[LOJA_ID] resolve_success fonte=get_apos_espera');
          return trimmed;
        }
      } catch (e, st) {
        logE('[LOJA_ID] get_apos_espera_falhou', error: e, st: st);
      }
      // Web: Auth pode ainda não ter restaurado (ex.: abriu /vendas direto na URL); aguardar e retentar
      if (FirebaseAuth.instance.currentUser == null) {
        logD('[STORE_SCREEN] Web: aguardando Auth restaurar (até 5s)...');
        try {
          await FirebaseAuth.instance.authStateChanges()
              .where((u) => u != null && !u.isAnonymous)
              .first
              .timeout(const Duration(seconds: 5), onTimeout: () => null);
          final id = await StoreResolverFacade.resolveForAdminApp()
              .timeout(const Duration(seconds: 10), onTimeout: () => null);
          final trimmed = id?.trim() ?? '';
          if (trimmed.isNotEmpty && isValidForPublicLink(trimmed)) {
            logD('[LOJA_ID] resolve_success fonte=StoreResolver_apos_auth_stream');
            return trimmed;
          }
        } catch (e, st) {
          logE('[LOJA_ID] resolve_apos_auth_stream_falhou', error: e, st: st);
        }
      }
    }

    // Fallback final (WEB): só Hive se usuário Firebase bater com sessão (ver _resolveSafeWebHiveFallback).
    if (kIsWeb) {
      try {
        final webFallback = await _resolveSafeWebHiveFallback();
        if (webFallback != null && webFallback.isNotEmpty) return webFallback;
      } catch (e, st) {
        logE('[LOJA_ID] web_fallback_exception', error: e, st: st);
      }
    }

    logW('[LOJA_ID] resolve_failed_no_safe_context motivo=getWithTimeout_esgotado');
    return null;
  }

  /// Igual a [getWithTimeout], mas se ainda assim vier vazio chama [get].
  ///
  /// Motivo: em APK, [getWithTimeout] **não** usa Hive como fallback quando o
  /// Firestore/Auth atrasam ou falham; os dados locais (ex.: `lancamentos_financeiros_*`)
  /// ficam em boxes nomeadas com `store_id` já persistido em `sessao`/`config`.
  /// Sem este passo, a Gestão Financeira pode abrir com outro critério de loja ou
  /// sem loja — parecendo que os lançamentos “sumiram”.
  static Future<String?> getWithTimeoutThenSessionFallback({
    Duration? timeout,
  }) async {
    final first = await getWithTimeout(timeout: timeout);
    final t = first?.trim() ?? '';
    if (t.isNotEmpty) return t;

    try {
      final second = await get();
      final g = second?.trim() ?? '';
      if (g.isNotEmpty) {
        logD(
          '[LOJAID] origem=getWithTimeoutThenSessionFallback retorno=$g motivo=fallback get() após timeout',
        );
        return g;
      }
    } catch (e) {
      debugPrint(
        '[LOJAID] getWithTimeoutThenSessionFallback: get() erro (type=${e.runtimeType})',
      );
    }
    return null;
  }

  /// Fallback seguro para WEB usando Hive (somente com [FirebaseAuth] + sessão alinhados).
  /// Não usa candidato sem usuário logado com e-mail verificável = mesmo principal em sessão.
  static Future<String?> _resolveSafeWebHiveFallback() async {
    if (!kIsWeb) return null;

    final user = FirebaseAuth.instance.currentUser;
    final authEmail = (user?.email ?? '').trim().toLowerCase();
    if (user == null || authEmail.isEmpty) {
      logW(
        '[LOJA_ID] web_fallback_rejected motivo=no_firebase_user_or_email',
      );
      return null;
    }

    final sessaoBox = Hive.isBoxOpen('sessao')
        ? Hive.box('sessao')
        : await Hive.openBox('sessao');
    final cfgBox = Hive.isBoxOpen('config')
        ? Hive.box('config')
        : await Hive.openBox('config');

    final cachedUserEmail =
        (sessaoBox.get('usuario_logado_email', defaultValue: '') ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final cachedUserLegacy =
        (sessaoBox.get('usuario_logado', defaultValue: '') ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final cachedPrincipal =
        cachedUserEmail.isNotEmpty ? cachedUserEmail : cachedUserLegacy;

    final cachedStoreId = normalizeFromBox(sessaoBox) ?? '';
    final cachedStoreIdCfg = normalizeFromBox(cfgBox) ?? '';
    final candidate = cachedStoreId.isNotEmpty ? cachedStoreId : cachedStoreIdCfg;

    if (candidate.isEmpty || !isValidForPublicLink(candidate)) {
      logW('[LOJA_ID] web_fallback_rejected motivo=candidate_invalido');
      return null;
    }

    if (cachedPrincipal.isEmpty) {
      logW('[LOJA_ID] web_fallback_rejected motivo=cachedPrincipal_vazio');
      return null;
    }

    if (authEmail != cachedPrincipal) {
      logW(
        '[LOJA_ID] web_fallback_rejected motivo=principal_mismatch',
      );
      return null;
    }

    logD('[LOJA_ID] web_fallback_used');
    return candidate;
  }

  static Future<String> ensureOrThrow() async {
    final id = await get();
    if (id == null || id.trim().isEmpty) {
      throw StateError('Nenhuma loja ativa encontrada (store_id).');
    }
    return id.trim();
  }

  static Future<String> ensure() => ensureOrThrow();

  // ============================================================
  // ✅ SET (estático): grava SEM DESTRUIR slug
  // ============================================================
  static Future<void> set(String lojaId) async {
  final id = lojaId.trim();
  if (id.isEmpty) throw ArgumentError('lojaId não pode ser vazio.');

  // 1) StoreContext (fonte viva)
  await StoreContext.set(id);

  // 2) sessao
  final Box sessao = Hive.isBoxOpen('sessao')
      ? Hive.box('sessao')
      : await Hive.openBox('sessao');

  await sessao.put('store_id', id);

  // ✅ NÃO escrever store_slug/loja_slug com store_id (slug ≠ id)
  // Se quiser garantir slug, isso deve ser feito em outro fluxo (LojaConfig / onboarding)

  // 3) config
  final Box cfg = Hive.isBoxOpen('config')
      ? Hive.box('config')
      : await Hive.openBox('config');

  await cfg.put('store_id', id);

  // ✅ NÃO escrever store_slug/loja_slug com store_id
}


  // ============================================================
  // ✅ CLEAR: limpa e invalida sessão (chame no logout)
  // ============================================================
  static Future<void> clear() async {
    _instance?._lojaId = null;
    _instance?.notifyListeners();

    // ✅ limpa cache + apaga store_id das boxes (sem apagar slug)
    await StoreContext.clear();

    // (redundância segura — se alguma box falhar no StoreContext, garante aqui)
    try {
      final Box sessao = Hive.isBoxOpen('sessao')
          ? Hive.box('sessao')
          : await Hive.openBox('sessao');
      await sessao.delete('store_id');
    } catch (_) {}

    try {
      final Box cfg = Hive.isBoxOpen('config')
          ? Hive.box('config')
          : await Hive.openBox('config');
      await cfg.delete('store_id');
    } catch (_) {}
  }
}
