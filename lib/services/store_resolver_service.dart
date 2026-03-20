// lib/services/store_resolver_service.dart
// 🔒 FONTE ÚNICA DA VERDADE PARA LOJA ATIVA (APENAS APP ADMIN — APK / WEB)
// Cada usuário (dono da loja) tem UMA loja FIXA baseada no UID - IMUTÁVEL
// ✅ PADRONIZADO: Usa slug baseado no email (como natypolylopes1997@gmail.com)
//
// ⚠️ Este serviço é EXCLUSIVO do app da loja (admin). O cadastro/login do
//    CLIENTE no catálogo (quem compra) usa ClienteAuthService e lojas/{id}/clientes;
//    NUNCA users/ ou usuarios/ — não misturar os dois fluxos.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';

import '../core/loja_id_adapter.dart';
import '../core/logger.dart';
import 'public_store_link_helper.dart';

class StoreResolverService {
  StoreResolverService._();

  static String• _cache;
  static String• _cachedUid;
  static bool _authListenerRegistered = false;

  // ================================================================
  // 🔒 LOJA FIXA POR USUÁRIO - IMUTÁVEL
  // ================================================================

  /// Todas as lojas usam a mesma regra: Firestore (users/{uid}, usuarios/{email})
  /// e slug do email. Garanta no Firestore: users e usuarios com store_id correto.

  /// Placeholders que NUNCA devem ser retornados (catálogo/link inválidos).
  static const _placeholdersInvalidos = {'minha-loja', 'minha_loja', 'masterpalm'};
  static bool _isPlaceholder(String• s) =>
      s != null && _placeholdersInvalidos.contains(s.trim().toLowerCase());

  /// Resolve a loja FIXA do usuário
  /// ⚠️ NUNCA muda - um usuário = uma loja para sempre
  /// ✅ PADRONIZADO: Prioridade de resolução:
  ///    1) Auth (aguarda até 5s no Web se currentUser ainda null)
  ///    2) Cache local
  ///    3) Firestore users/{uid}.store_id
  ///    4) Firestore usuarios/{email}.store_id
  ///    5) Hive sessao/config (offline, mesmo usuário)
  ///    6) Slug baseado no email
  static Future<String?> resolve() async {
    logD('[STORE_RESOLVE] origem=StoreResolverService.resolve inicio');
    final user0 = FirebaseAuth.instance.currentUser;
    logD('[STORE_RESOLVE] auth uid=${user0?.uid ?• "null"} email=${user0?.email ?• "null"}');
    try {
      final sessao = Hive.isBoxOpen('sessao') • Hive.box('sessao') : await Hive.openBox('sessao');
      final cfg = Hive.isBoxOpen('config') • Hive.box('config') : await Hive.openBox('config');
      logD('[STORE_RESOLVE] sessao.store_id=${sessao.get("store_id")} config.store_id=${cfg.get("store_id")} usuario_logado_email=${sessao.get("usuario_logado_email")} usuario_logado=${sessao.get("usuario_logado")}');
    } catch (e) {
      logW('[STORE_RESOLVE] leitura inicial de sessao/config falhou (type=${e.runtimeType})');
    }

    _ensureAuthListener();

    var currentUid = FirebaseAuth.instance.currentUser?.uid;
    // Web: Auth pode demorar a restaurar sessão (persistência); aguardar mais tempo
    const authWaitSeconds = kIsWeb • 15 : 5;
    if (currentUid == null) {
      logD('[STORE_RESOLVE] currentUser null, aguardando auth (até ${authWaitSeconds}s)...');
      try {
        await FirebaseAuth.instance.authStateChanges()
            .where((u) => u != null)
            .first
            .timeout(const Duration(seconds: authWaitSeconds), onTimeout: () => null);
        currentUid = FirebaseAuth.instance.currentUser?.uid;
      } catch (e) {
        logW('[STORE_RESOLVE] espera authStateChanges falhou (type=${e.runtimeType})');
      }
      if (currentUid == null) {
        // WEB: Auth pode atrasar na restauração. Como fallback seguro, usar store_id do Hive
        // somente quando houver principal de sessão e candidate válido (sem placeholders).
        if (kIsWeb) {
          final safeFromHive = await _safeHiveFallbackWhenAuthNull();
          if (safeFromHive != null && safeFromHive.isNotEmpty) {
            logD('[STORE_RESOLVE] source=hive_auth_pending lojaId=$safeFromHive');
            _cache = safeFromHive;
            _cachedUid = null;
            return safeFromHive;
          }
        }
        // Se não conseguiu fallback seguro, mantém null.
        logW('[STORE_RESOLVE] source=none lojaId=null (auth null após espera)');
        return null;
      }
      logD('[STORE_RESOLVE] Auth pronto, uid=$currentUid');
    }

    // Cache hit com mesmo UID (ignora placeholder)
    if (_cache != null && _cachedUid == currentUid && !_isPlaceholder(_cache)) {
      logD('[STORE_RESOLVE] source=cache lojaId=$_cache');
      return _cache;
    }

    String• lojaFixa;
    String resolvedSource = 'none';

    // ✅ 1) Cache em memória (já logado acima como "Cache: $_cache")
    // Cache hit já retornou; aqui lojaFixa ainda é null.

    // ✅ 2) Verificar Firestore users/{uid}.store_id (já configurado)
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .get()
          .timeout(const Duration(seconds: 5));

      if (userDoc.exists) {
        final storeId = normalizeFromMap(userDoc.data());
        if (storeId != null && storeId.isNotEmpty && !_isPlaceholder(storeId)) {
          lojaFixa = storeId;
          resolvedSource = 'users_doc';
          logD('[STORE_RESOLVE] source=users_doc lojaId=$lojaFixa');
        }
      }
    } catch (e, st) {
      logE('[STORE_RESOLVE] Erro Firestore users/{uid} (type=${e.runtimeType})', error: e, st: st);
    }

    // ✅ 3) Verificar Firestore usuarios/{email}.store_id (mesma regra para todas as lojas)
    if (lojaFixa == null) {
      final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
      if (email != null && email.isNotEmpty) {
        try {
          final usuarioDoc = await FirebaseFirestore.instance
              .collection('usuarios')
              .doc(email)
              .get()
              .timeout(const Duration(seconds: 5));

          if (usuarioDoc.exists) {
            final storeId = normalizeFromMap(usuarioDoc.data());
            if (storeId != null && storeId.isNotEmpty && !_isPlaceholder(storeId)) {
              lojaFixa = storeId;
              resolvedSource = 'usuarios_doc';
              logD('[STORE_RESOLVE] source=usuarios_doc lojaId=$lojaFixa');
            }
          }
        } catch (e, st) {
          logE('[STORE_RESOLVE] Erro Firestore usuarios/{email} (type=${e.runtimeType})', error: e, st: st);
        }
      }
    }

    // ✅ 5b) Hive sessao/config APENAS quando Firestore falhou (offline) E usuario_logado == currentUser
    // No Web, IndexedDB é compartilhado; validar sempre que usuario_logado coincide.
    if (lojaFixa == null) {
      try {
        final currentEmail = (FirebaseAuth.instance.currentUser?.email ?• '').trim().toLowerCase();
        final Box sessao = Hive.isBoxOpen('sessao')
            • Hive.box('sessao')
            : await Hive.openBox('sessao');
        final cachedUserEmail = (sessao.get('usuario_logado_email') ?• '')
            .toString()
            .trim()
            .toLowerCase();
        final cachedUserLegacy = (sessao.get('usuario_logado') ?• '')
            .toString()
            .trim()
            .toLowerCase();
        final cachedUser = cachedUserEmail.isNotEmpty • cachedUserEmail : cachedUserLegacy;
        if (currentEmail.isNotEmpty &&
            cachedUser.isNotEmpty &&
            currentEmail == cachedUser) {
          final rawId = normalizeFromBox(sessao);
          if (rawId != null && rawId.isNotEmpty && !_isPlaceholder(rawId)) {
            lojaFixa = rawId;
            resolvedSource = 'hive_sessao_offline';
            logD('[BOOT-FALLBACK] [STORE_RESOLVE] source=hive_sessao_offline lojaId=$lojaFixa');
          }
        }
        if (lojaFixa == null) {
          final Box cfg = Hive.isBoxOpen('config')
              • Hive.box('config')
              : await Hive.openBox('config');
          if (currentEmail.isNotEmpty && cachedUser.isNotEmpty && currentEmail == cachedUser) {
            final rawId = normalizeFromBox(cfg);
            if (rawId != null && rawId.isNotEmpty && !_isPlaceholder(rawId)) {
              lojaFixa = rawId;
              resolvedSource = 'hive_config_offline';
              logD('[BOOT-FALLBACK] [STORE_RESOLVE] source=hive_config_offline lojaId=$lojaFixa');
            }
          }
        }
      } catch (e, st) {
        logE('[STORE_RESOLVE] Erro Hive fallback offline (type=${e.runtimeType})', error: e, st: st);
      }
    }

    // ✅ 6) Slug baseado no email (fallback) — loja única por usuário, sem colisão
    if (lojaFixa == null) {
      final email = FirebaseAuth.instance.currentUser?.email ?• '';
      lojaFixa = await _resolveUniqueSlug(email, currentUid);
      resolvedSource = 'slug_fallback';
      logD('[STORE_RESOLVE] source=slug_fallback lojaId=$lojaFixa');
    }

    // Garantir que a loja existe no Firestore (não bloqueia quando offline)
    _ensureLojaExists(currentUid, lojaFixa).catchError((e, st) {
      logE('[STORE_RESOLVE] ensureLojaExists falhou (type=${e.runtimeType})', error: e, st: st);
    });

    // Persistir e cachear (persistência não deve bloquear retorno no Web)
    try {
      await _persist(lojaFixa);
    } catch (e, st) {
      logE('[STORE_RESOLVE] Erro ao persistir (Hive); lojaId=$lojaFixa (type=${e.runtimeType})', error: e, st: st);
    }
    _cache = lojaFixa;
    _cachedUid = currentUid;

    logD('[STORE_RESOLVE] source=$resolvedSource lojaId=$lojaFixa');
    return lojaFixa;
  }

  /// ✅ Gera slug amigável baseado no email (padrão igual ao TenantService)
  static String _makeSlugFromEmail(String email, String uid) {
    if (email.isEmpty) {
      return 'loja-$uid';
    }

    var slug = email.toLowerCase().trim();
    // Pega apenas a parte antes do @
    slug = slug.split('@').first;
    // Remove caracteres especiais, mantém apenas letras, números e hífen
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    // Remove hífens duplicados
    slug = slug.replaceAll(RegExp(r'-{2,}'), '-');
    // Remove hífens no início e fim
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');

    return slug.isEmpty • 'loja-$uid' : slug;
  }

  /// Resolve slug único: se a loja já existe e é de outro dono, usa base-1, base-2, ...
  /// Mesmo critério do login com Google para novas contas — sem misturar lojas.
  static Future<String> _resolveUniqueSlug(String email, String uid) async {
    final base = _makeSlugFromEmail(email, uid);
    String candidate = base;
    int i = 0;
    try {
      while (true) {
        final snap = await FirebaseFirestore.instance.doc('lojas/$candidate').get().timeout(const Duration(seconds: 3));
        if (!snap.exists) return candidate;
        final ownerUid = snap.data()?['ownerUid'] as String?;
        if (ownerUid == uid) return candidate;
        i++;
        candidate = '$base-$i';
      }
    } catch (e, st) {
      logE('[STORE_RESOLVE] _resolveUniqueSlug falhou, usando base (type=${e.runtimeType})', error: e, st: st);
      return base;
    }
  }

  /// Garante que a loja existe no Firestore
  static Future<void> _ensureLojaExists(String uid, String lojaId) async {
    try {
      final lojaDoc = FirebaseFirestore.instance.doc('lojas/$lojaId');
      final snapshot = await lojaDoc.get().timeout(const Duration(seconds: 5));

      if (!snapshot.exists) {
        logD('📝 [STORE-RESOLVER] Criando loja nova');

        // Criar loja
        await lojaDoc.set({
          'lojaId': lojaId,
          'id': lojaId,
          'slug': lojaId,
          'ownerUid': uid,
          'nome': 'Minha Loja',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'ativo': true,
        });

        // Criar config
        await lojaDoc.collection('config').doc('config').set({
          'lojaId': lojaId,
          'slug': lojaId,
          'nome': 'Minha Loja',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Criar draft_config
        await lojaDoc.collection('draft_config').doc('config').set({
          'lojaId': lojaId,
          'slug': lojaId,
          'nome': 'Minha Loja',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Criar members/{uid} (owner) — mesmo fluxo do login Google
        final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
        await lojaDoc.collection('members').doc(uid).set({
          'role': 'owner',
          'email': email ?• '',
          'joinedAt': FieldValue.serverTimestamp(),
        });

        logD('✅ [STORE-RESOLVER] Loja criada');
      }

      // ✅ Sincronizar users/{uid}
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'store_id': lojaId,
            'ownerOf': lojaId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // ✅ Sincronizar usuarios/{email} (padrão igual natypolylopes1997@gmail.com)
      final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim();
      if (email != null && email.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(email)
            .set({
              'store_id': lojaId,
              'authUid': uid,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        logD('✅ [STORE-RESOLVER] Sincronizado usuarios store_id');
      }

    } catch (e, st) {
      logE('⚠️ [STORE-RESOLVER] Erro ao verificar/criar loja (type=${e.runtimeType})', error: e, st: st);
    }
  }

  // ================================================================
  // 🔒 SET - BLOQUEADO (LOJA É IMUTÁVEL)
  // ================================================================

  /// ⚠️ BLOQUEADO - A loja é FIXA por usuário e não pode ser alterada
  /// Esta função agora apenas loga um aviso e ignora a tentativa
  static Future<void> set(String storeId) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    logD('🚫 [STORE-RESOLVER] Tentativa de SET bloqueada!');
    logD('   Tentou definir: $storeId');
    logD('   UID atual: $currentUid');
    logD('   ⚠️ A loja é FIXA por usuário e não pode ser alterada!');

    // Apenas resolver a loja correta
    await resolve();
  }

  // ================================================================
  // CLEAR - APENAS LIMPA CACHE
  // ================================================================

  static Future<void> clear() async {
    logD('🗑️ [STORE-RESOLVER] Limpando cache...');
    _cache = null;
    _cachedUid = null;

    try {
      final sessao = await _openBox('sessao');
      await sessao.delete('store_id');
    } catch (_) {}

    try {
      final config = await _openBox('config');
      await config.delete('store_id');
    } catch (_) {}

    logD('✅ [STORE-RESOLVER] Cache limpo (loja será recalculada do UID)');
  }

  // ================================================================
  // INVALIDATE
  // ================================================================

  static void invalidate() {
    _cache = null;
    _cachedUid = null;
    logD('🔄 [STORE-RESOLVER] Cache invalidado');
  }

  // ================================================================
  // AUTH LISTENER
  // ================================================================

  static void _ensureAuthListener() {
    if (_authListenerRegistered) return;

    FirebaseAuth.instance.authStateChanges().listen((User• user) {
      final currentUid = user?.uid;
      // Só limpar cache quando trocar para OUTRO usuário (uid diferente).
      // Não limpar quando user == null: no Web o Auth pode emitir null brevemente
      // (refresh de token, aba em background) e ao voltar para Vendas/Clientes
      // o cache já estaria vazio e daria "Não foi possível carregar a loja".
      if (currentUid != null && _cachedUid != null && _cachedUid != currentUid) {
        logD('🔐 [STORE-RESOLVER] Auth mudou de usuário, limpando cache');
        _cache = null;
        _cachedUid = null;
      }
    });

    _authListenerRegistered = true;
  }

  // ================================================================
  // HELPERS
  // ================================================================

  static Future<Box> _openBox(String name) async {
    return Hive.isBoxOpen(name) • Hive.box(name) : await Hive.openBox(name);
  }

  static Future<void> _persist(String storeId) async {
    try {
      final sessao = await _openBox('sessao');
      await sessao.put('store_id', storeId);

      final config = await _openBox('config');
      await config.put('store_id', storeId);
      await config.put('last_loja_id', storeId);
    } catch (e, st) {
      logE('⚠️ [STORE-RESOLVER] Erro ao persistir (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Fallback seguro para WEB quando auth ainda não está pronto.
  /// Regras:
  /// - principal de sessão obrigatório (usuario_logado_email ou usuario_logado)
  /// - store_id obrigatório e válido (não placeholder)
  static Future<String?> _safeHiveFallbackWhenAuthNull() async {
    try {
      final sessao = await _openBox('sessao');
      final cfg = await _openBox('config');

      final principalEmail = (sessao.get('usuario_logado_email') ?• '')
          .toString()
          .trim()
          .toLowerCase();
      final principalLegacy = (sessao.get('usuario_logado') ?• '')
          .toString()
          .trim()
          .toLowerCase();
      final principal = principalEmail.isNotEmpty • principalEmail : principalLegacy;
      if (principal.isEmpty) {
        logW('[STORE_RESOLVE] hive fallback negado: principal vazio');
        return null;
      }

      final fromSessao = normalizeFromBox(sessao);
      final fromConfig = normalizeFromBox(cfg);
      final candidate = (fromSessao != null && fromSessao.trim().isNotEmpty)
          • fromSessao.trim()
          : (fromConfig ?• '').trim();
      if (candidate.isEmpty || !isValidForPublicLink(candidate) || _isPlaceholder(candidate)) {
        logW('[STORE_RESOLVE] hive fallback negado: candidate inválido ($candidate)');
        return null;
      }

      logD('[STORE_RESOLVE] hive fallback aceito (auth pendente): principal=$principal candidate=$candidate');
      return candidate;
    } catch (e, st) {
      logE('[STORE_RESOLVE] hive fallback erro (type=${e.runtimeType})', error: e, st: st);
      return null;
    }
  }

  // ================================================================
  // DEBUG
  // ================================================================

  static Future<void> debug() async {
    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    logD('🔍 [STORE-RESOLVER] DEBUG STATE');
    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    logD('UID atual: $uid');
    logD('Cache: $_cache');
    logD('Cached UID: $_cachedUid');

    try {
      final sessao = await _openBox('sessao');
      logD('Hive sessao["store_id"]: ${sessao.get("store_id")}');
    } catch (e, st) {
      logE('Hive sessao: ERRO (type=${e.runtimeType})', error: e, st: st);
    }

    try {
      final config = await _openBox('config');
      logD('Hive config["store_id"]: ${config.get("store_id")}');
    } catch (e, st) {
      logE('Hive config: ERRO (type=${e.runtimeType})', error: e, st: st);
    }

    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          logD('Firestore users/{uid}.store_id: ${doc.data()?["store_id"]}');
        }
      } catch (e, st) {
        logE('Firestore users: ERRO (type=${e.runtimeType})', error: e, st: st);
      }
    }

    logD('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
}
