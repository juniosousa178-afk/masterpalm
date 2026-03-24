// lib/screens/app_start_router.dart - CORREÇÕES

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/feature_flags.dart';
import '../core/logger.dart';
import '../core/remote_config_keys.dart';
import '../models/user_profile.dart';
import '../services/planos_service.dart';
import '../services/user_profile_resolver.dart';
import '../services/remote_config_safe_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/store_resolver_service.dart';
import '../utils/role_utils.dart'; // ✅ Utilitário centralizado de roles
import '../utils/last_route_observer.dart'; // ✅ Restaurar tela ao voltar do segundo plano

class AppStartRouter extends StatefulWidget {
  const AppStartRouter({super.key});

  @override
  State<AppStartRouter> createState() => _AppStartRouterState();
}

class _AppStartRouterState extends State<AppStartRouter> {
  bool _busy = true;
  String _msg = 'Iniciando...';

  // ✅ CORREÇÃO: Usar const (lowercase)
  static const String _routeLogin = '/login';
  static const String _routePlanos = '/planos';
  static const String _routeHome = '/home';

  static const Set<String> _rootAdminEmailsHardcoded = {
    'masterpalm26@gmail.com',
    'masterpalm@gmail.com',
    'admin@masterpalm.com',
  };

  Set<String> _getRootAdminEmails() {
    if (!RemoteConfigSafeService.isFlagOn(rcEnableDynamicRootAdmins, fallback: false)) {
      return _rootAdminEmailsHardcoded;
    }
    final list = RemoteConfigSafeService.getStringListFromJson(
      rcRootAdminEmailsJson,
      fallback: _rootAdminEmailsHardcoded.toList(),
    );
    return list.isEmpty ? _rootAdminEmailsHardcoded : list.toSet();
  }

  /// Resolve perfil do usuário atual via UserProfileResolver (só usado quando flag ON).
  Future<UserProfile?> _resolveUserProfile({required bool isRootEmail}) async {
    return UserProfileResolver.resolveCurrentUserProfile(isRoot: isRootEmail);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  bool _isFirebaseReady() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _routeWithoutFirebase() async {
    logW(
      '⚠️ [ROUTE_GUARD] Firebase indisponível. Entrando em modo seguro sem Auth.',
    );
    _setBusy('Conexão com Firebase indisponível. Tente novamente em instantes.');
  }

  Future<void> _run() async {
    try {
      logD(
        '[ROUTE_GUARD] AppStartRouter._run inicio uri=${Uri.base} path=${Uri.base.path}',
      );
      _setBusy('Verificando sessão...');
      logD('[BOOT-ROUTER] Iniciando verificação de sessão');

      if (!_isFirebaseReady()) {
        await _routeWithoutFirebase();
        return;
      }

      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      logD(
        '[ROUTE_GUARD] auth uid=${user?.uid ?? "null"} email=${user?.email ?? "null"}',
      );

      // Usuário só desloga ao clicar em Sair, limpar dados do app ou reinstalar
      if (user == null) {
        logD('[BOOT-BLOCK] Sem usuário logado → /login');
        _go(_routeLogin);
        return;
      }

      _setBusy('Carregando dados locais...');
      await Hive.openBox('sessao');
      await Hive.openBox('config');

      final sessao = Hive.box('sessao');
      final config = Hive.box('config');

      // Sessão de cliente do catálogo não deve abrir o app admin; redirecionar para login.
      if (sessao.get('auth_context') == 'cliente') {
        logD('[BOOT-BLOCK] Sessão de cliente do catálogo → /login');
        try {
          await auth.signOut();
        } catch (_) {}
        sessao.delete('auth_context');
        sessao.delete('cliente_loja_id');
        if (mounted) _go(_routeLogin);
        return;
      }

      final email = (user.email ?? '').trim().toLowerCase();
      final uid = user.uid;
      logD('[BOOT-AUTH] Usuário logado: $email (uid: $uid)');
      final storeInSessao = (sessao.get('store_id') ?? sessao.get('lojaId') ?? '').toString().trim();
      logD('[BOOT-STORE] Boxes Hive abertos | store_id em sessao=${storeInSessao.isNotEmpty ? storeInSessao : "vazio"}');

      sessao.put('usuario_logado', email);

      final rootEmails = _getRootAdminEmails();
      final isRootEmail = rootEmails.contains(email);

      if (isRootEmail) {
        sessao.put('tipo_usuario', 'programador');
        sessao.put('is_root', true);
        sessao.put('role', 'programador');
      } else {
        sessao.put('is_root', false);
      }

      // ✅ ROOT: abre home na hora e prepara loja em background
      if (isRootEmail) {
        logD(
            '🔑 [ROUTER] ROOT USER - abrindo home e preparando loja em background');
        _goHomeOrRestore();
        _bindActiveStore(sessao: sessao, config: config, isRoot: true);
        return;
      }

      // ✅ Atalho VENDEDOR: se já tem store_id em cache, abre home e atualiza em background
      final cachedTipo =
          (sessao.get('tipo_usuario') ?? sessao.get('role') ?? '')
              .toString()
              .trim();
      final cachedStore = (sessao.get('store_id') ?? sessao.get('lojaId') ?? '')
          .toString()
          .trim();
      if (cachedTipo == 'vendedor' && cachedStore.isNotEmpty) {
        logD(
            '🚀 [ROUTER] Vendedor com sessão em cache → abrindo home e validando em background');
        _goHomeOrRestore();
        _runVendedorValidationInBackground(
            uid: uid, email: email, sessao: sessao, config: config);
        return;
      }

      // ✅ Verificação de e-mail: só para contas NOVAS (antigas não precisam)
      if (!user.emailVerified) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get()
              .timeout(const Duration(seconds: 2));
          final requiresVerification =
              userDoc.data()?['emailVerificationRequired'] == true;
          if (requiresVerification) {
            logD(
                '📧 [ROUTER] E-mail não verificado (conta nova) → /verify_email');
            _go('/verify_email');
            return;
          }
        } catch (_) {}
      }

      // ✅ Carregar role do usuário (duas leituras em paralelo para acelerar)
      // ✅ Timeout 5s + retry: evita tratar admin como vendedor quando Firestore demora (cold start)
      _setBusy('Verificando perfil...');
      String userRole = 'vendedor';
      String? vendedorStoreId;
      bool gotProfileFromResolver = false;
      if (kEnableUnifiedUserProfileResolver) {
        final profile = await _resolveUserProfile(isRootEmail: isRootEmail);
        if (profile == null) {
          // fallback já feito por gotProfileFromResolver false
        } else if (!profile.isComplete) {
          logW(
            '[ROUTER] Perfil resolvido incompleto (${profile.sourceCollection}) '
            'role=${profile.role} storeId=${profile.storeId} -> fallback fetchRoleAndStore',
          );
          // gotProfileFromResolver permanece false -> executa fetchRoleAndStore
        } else {
          userRole = profile.role;
          vendedorStoreId = profile.storeId;
          gotProfileFromResolver = true;
        }
      }

      if (!gotProfileFromResolver) {
      Future<Map<String, dynamic>?> fetchRoleAndStore() async {
        const timeout = Duration(seconds: 5);
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get()
            .timeout(timeout);
        final usuarioDoc = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(email)
            .get()
            .timeout(timeout);

        String role = 'vendedor';
        String? storeId;

        if (userDoc.exists) {
          final d = userDoc.data() ?? <String, dynamic>{};
          role = (d['role'] ?? d['tipo'] ?? d['tipo_usuario'] ?? 'vendedor')
              .toString().trim().toLowerCase();
          storeId = (d['store_id'] ?? d['storeId'] ?? d['ownerStoreId'] ?? '')
              .toString().trim();
        }
        if ((role == 'vendedor' || storeId == null || storeId.isEmpty) &&
            usuarioDoc.exists) {
          final d = usuarioDoc.data() ?? <String, dynamic>{};
          role = (d['tipo'] ?? d['role'] ?? role).toString().trim().toLowerCase();
          storeId = (d['store_id'] ?? d['ownerStoreId'] ?? storeId ?? '')
              .toString().trim();
        }
        // Conta criada no login (Google) cria loja mas pode não ter users/{uid}.
        // Se usuário é dono de uma loja, tratar como admin.
        if (role == 'vendedor' || (storeId == null || storeId.isEmpty)) {
          try {
            final lojasSnap = await FirebaseFirestore.instance
                .collection('lojas')
                .where('ownerUid', isEqualTo: uid)
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 3));
            if (lojasSnap.docs.isNotEmpty) {
              role = 'admin';
              storeId = lojasSnap.docs.first.id;
            }
          } catch (_) {}
        }
        return {'role': role, 'storeId': storeId?.isEmpty == true ? null : storeId};
      }

      try {
        var data = await fetchRoleAndStore();
        if (data != null) {
          userRole = data['role'] as String? ?? 'vendedor';
          vendedorStoreId = data['storeId'] as String?;
        }
      } on TimeoutException catch (e) {
        logW('⚠️ [ROUTER] Timeout ao buscar role (1ª tentativa) (type=${e.runtimeType})');
        try {
          logD('🔄 [ROUTER] Retentando busca do role (2ª tentativa)...');
          final data = await fetchRoleAndStore();
          if (data != null) {
            userRole = data['role'] as String? ?? 'vendedor';
            vendedorStoreId = data['storeId'] as String?;
          }
        } catch (e2) {
          logW('⚠️ [ROUTER] Retry falhou ao buscar role (type=${e2.runtimeType})');
          // Fallback: StoreResolver obtém store_id (5s). Em seguida tenta role em cache.
          final resolved = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base);
          if (resolved != null && resolved.isNotEmpty) {
            vendedorStoreId = resolved;
            logD('📋 [ROUTER] Store obtido via StoreResolver');
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get()
                  .timeout(const Duration(seconds: 3));
              if (userDoc.exists) {
                final d = userDoc.data() ?? {};
                userRole = (d['role'] ?? d['tipo'] ?? d['tipo_usuario'] ?? userRole)
                    .toString().trim().toLowerCase();
                logD('📋 [ROUTER] Role obtido no fallback: $userRole');
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        logW('⚠️ [ROUTER] Erro ao buscar role (type=${e.runtimeType})');
        final resolved = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base);
        if (resolved != null && resolved.isNotEmpty) {
          vendedorStoreId = resolved;
          logD('📋 [ROUTER] Store obtido via StoreResolver');
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get()
                .timeout(const Duration(seconds: 3));
            if (userDoc.exists) {
              final d = userDoc.data() ?? {};
              userRole = (d['role'] ?? d['tipo'] ?? d['tipo_usuario'] ?? userRole)
                  .toString().trim().toLowerCase();
              logD('📋 [ROUTER] Role obtido no fallback: $userRole');
            }
          } catch (_) {}
        }
      }
      }

      // 📴 Offline: usar role e store da sessão quando Firestore não respondeu
      if (vendedorStoreId == null || vendedorStoreId.isEmpty) {
        final cachedStore = (sessao.get('store_id') ?? sessao.get('lojaId') ?? '').toString().trim();
        if (cachedStore.isNotEmpty) {
          vendedorStoreId = cachedStore;
          logD('📴 [ROUTER] Store da sessão (offline)');
        }
      }
      if (userRole == 'vendedor' && (sessao.get('tipo_usuario') ?? sessao.get('role')) != null) {
        userRole = (sessao.get('tipo_usuario') ?? sessao.get('role') ?? userRole).toString().trim().toLowerCase();
      }

      logD('📋 [ROUTER] Role do usuário: $userRole');

      // ✅ VENDEDOR: BYPASS DE PLANO - usa plano do admin/loja
      if (userRole == 'vendedor') {
        logD(
            '👤 [ROUTER] VENDEDOR detectado - bypass de verificação de plano');

        if (vendedorStoreId == null || vendedorStoreId.isEmpty) {
          logD('❌ [ROUTER] Vendedor sem loja vinculada');
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
          if (mounted) _go(_routeLogin);
          return;
        }

        // Salvar store_id do vendedor na sessão
        sessao.put('store_id', vendedorStoreId);
        sessao.put('storeId', vendedorStoreId);
        sessao.put('tipo_usuario', 'vendedor');
        sessao.put('role', 'vendedor');

        logD('✅ [ROUTER] Vendedor vinculado à loja');

        await _bindActiveStore(sessao: sessao, config: config, isRoot: false);
        _goHomeOrRestore();
        return;
      }

      // ✅ ADMIN/PROGRAMADOR: Verificar plano (usa cache de 1h para abrir o app mais rápido)
      _setBusy('Verificando plano...');
      logD(
          '📋 [ROUTER] Verificando plano do usuário (admin/programador)');

      final planCacheUntil = sessao.get('plan_cache_until');
      final planExpired = sessao.get('plan_expired') == true;
      final cacheValid = planCacheUntil is int &&
          planCacheUntil > DateTime.now().millisecondsSinceEpoch &&
          !planExpired;

      final planos = PlanosService();
      PlanInfo? plan;
      if (cacheValid) {
        logD('✅ [ROUTER] Plano em cache, entrando na home');
        plan = PlanInfo(
          planId: (sessao.get('plan_plan_id') ?? 'free_limited').toString(),
          status: 'active',
          trialing: false,
          currentPeriodEnd: null,
          trialUsed: true,
          manualOverride: false,
        );
      } else {
        plan = await planos
            .fetchCurrentPlan(uid: uid, email: email)
            .timeout(const Duration(seconds: 5), onTimeout: () {
          logW('⚠️ [ROUTER] Timeout ao buscar plano, continuando...');
          return null;
        });
        if (plan != null) {
          sessao.put('plan_cache_until',
              DateTime.now().millisecondsSinceEpoch + 3600000); // 1h
          sessao.put('plan_expired', plan.isExpired);
          sessao.put('plan_plan_id', plan.planId);
        }
      }

      if (plan == null) {
        // Offline ou timeout: usar plano em cache se existir
        final cachedPlanId = (sessao.get('plan_plan_id') ?? 'free_limited').toString();
        if (cachedPlanId.isNotEmpty) {
          logD('📴 [ROUTER] Usando plano em cache (offline/timeout): $cachedPlanId');
          plan = PlanInfo(
            planId: cachedPlanId,
            status: 'active',
            trialing: false,
            currentPeriodEnd: null,
            trialUsed: true,
            manualOverride: true,
          );
        }
        if (plan == null) {
          logD('❌ [ROUTER] Sem plano e sem cache → /planos');
          _go(_routePlanos);
          return;
        }
      }
      logD('✅ [ROUTER] Plano encontrado: ${plan.planId}');

      // Se for manualOverride (modo offline), pular validações de expiração
      if (!plan.manualOverride) {
        if (!plan.isLifetime) {
          if (plan.currentPeriodEnd == null) {
            await FirebaseAuth.instance.signOut();
            if (!mounted) return;
            _go(_routeLogin);
            return;
          }

          if (plan.isExpired) {
            // Opção B: free_trial_90d expirado → migra para free_limited (não bloqueia)
            if (plan.planId == PlanId.freeTrial90d) {
              try {
                await planos
                    .migrateToFreeLimited(uid: uid, email: email)
                    .timeout(const Duration(seconds: 3));
                logD(
                    '✅ [ROUTER] Trial expirado → migrado para free_limited');
                // Continua para home com plano limitado
              } catch (e) {
                logW('⚠️ Erro ao migrar para free_limited (type=${e.runtimeType})');
              }
            } else {
              // Planos pagos expirados: bloqueia (signOut)
              try {
                await planos
                    .markExpiredIfNeeded(uid: uid, email: email)
                    .timeout(const Duration(seconds: 1));
              } catch (e) {
                logW('⚠️ Erro ao marcar plano como expirado (type=${e.runtimeType})');
              }
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              _go(_routeLogin);
              return;
            }
          }
        }
      }

      await _syncPerfilFirestore(
        uid: uid,
        sessao: sessao,
        isRootEmail: isRootEmail,
        email: email,
      );

      await _bindActiveStore(
        sessao: sessao,
        config: config,
        isRoot: isRootEmail,
      );

      await _routeByRoleAndLoja(sessao);
    } catch (e, stack) {
      logE('❌ [ROUTER] ERRO (type=${e.runtimeType})', error: e, st: stack);
      // Em erro (sessão corrompida, rede, Firestore), redirecionar para login em vez de home para evitar dados errados.
      if (mounted) {
        if (_isFirebaseReady()) {
          try {
            await FirebaseAuth.instance.signOut();
          } catch (_) {}
        }
        if (mounted) _go(_routeLogin);
      }
    }
  }

  Future<void> _syncPerfilFirestore({
    required String uid,
    required Box sessao,
    required bool isRootEmail,
    required String email,
  }) async {
    _setBusy('Carregando perfil...');

    // ✅ ROOT: Migrar role no Firestore e NÃO deixar sobrescrever
    if (isRootEmail) {
      await RoleUtils.migrateIfNeeded(uid: uid, email: email);
      sessao.put('tipo_usuario', 'programador');
      sessao.put('role', 'programador');
      sessao.put('is_root', true);
      logD('🔑 [ROUTER] ROOT user - role fixado como programador');
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 1));

      if (!doc.exists) return;

      final raw = doc.data();
      final Map<String, dynamic> data =
          raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);

      final firestoreRole = (data['role'] ??
              data['tipo_usuario'] ??
              data['tipo'] ??
              data['userType'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();

      final localRole = (sessao.get('tipo_usuario') ?? '').toString();

      // ✅ Usar RoleUtils para resolver o role corretamente
      final resolvedRole = RoleUtils.resolveRole(
        email: email,
        firestoreRole: firestoreRole,
        localRole: localRole,
      );

      sessao.put('tipo_usuario', resolvedRole.name);
      sessao.put('role', resolvedRole.name);
      sessao.put('is_root', resolvedRole == UserRole.programador);

      logD('✅ [ROUTER] Role resolvido: ${resolvedRole.name}');

      final lojaId = (data['store_id'] ??
              data['storeId'] ??
              data['loja_id'] ??
              data['lojaId'])
          ?.toString()
          .trim();

      if (lojaId != null && lojaId.isNotEmpty) {
        sessao.put('loja_id', lojaId);
        sessao.put('lojaId', lojaId);
        sessao.put('store_id', lojaId);
        sessao.put('storeId', lojaId);
      }
    } catch (e) {
      // Sem internet ou erro - continuar com dados locais
      logW('⚠️ Erro ao carregar perfil do Firestore (modo offline) (type=${e.runtimeType})');
    }
  }

  Future<void> _bindActiveStore({
    required Box sessao,
    required Box config,
    required bool isRoot,
  }) async {
    _setBusy('Preparando loja...');
    logD('🏪 [ROUTER_GUARD] Resolvendo loja ativa');

    try {
      // FASE 3: Timeout maior no Web (cold start Firestore); fallback sessão quando resolve() null
      const timeoutSeconds = kIsWeb ? 6 : 3;
      String? loja = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base)
          .timeout(const Duration(seconds: timeoutSeconds), onTimeout: () {
        logW('⚠️ [ROUTER_GUARD] Timeout ao resolver loja (${timeoutSeconds}s)');
        return null;
      });

      if (kDebugMode) {
        logD('📌 [STORE_RESOLVE] resolveForRouter retornou: ${loja != null && loja.isNotEmpty ? loja : "null/vazio"}');
      }

      if (loja == null || loja.isEmpty) {
        if (isRoot) {
          loja = (config.get('last_loja_id') ?? '').toString().trim();
          logD('🔄 [ROUTER_GUARD] Root user, usando last_loja_id');
        }
      }

      // FASE 3: Não sair sem gravar quando já existir loja válida em sessão/config (evita perda no Web)
      if (loja == null || loja.isEmpty) {
        final fromSessao = (sessao.get('store_id') ?? sessao.get('lojaId') ?? '').toString().trim();
        final fromConfig = (config.get('last_loja_id') ?? config.get('store_id') ?? '').toString().trim();

        final current = _isFirebaseReady() ? FirebaseAuth.instance.currentUser : null;
        final currentEmail = (current?.email ?? '').trim().toLowerCase();
        final cachedUsuario = (sessao.get('usuario_logado') ?? '').toString().trim().toLowerCase();

        final sameUser = currentEmail.isNotEmpty &&
            cachedUsuario.isNotEmpty &&
            currentEmail == cachedUsuario;

        if (!sameUser) {
          logW(
            '⚠️ [ROUTER_GUARD] [STORE_SESSION] Fallback de sessão/config ignorado: usuário atual '
            'não coincide com usuario_logado. current=$currentEmail, cached=$cachedUsuario',
          );
        } else {
          if (fromSessao.isNotEmpty) {
            loja = fromSessao;
            logD(
              '🔄 [ROUTER_GUARD] [STORE_SESSION] Fallback sessão aceito → store_id=$loja (user=$currentEmail)',
            );
          } else if (fromConfig.isNotEmpty) {
            loja = fromConfig;
            logD(
              '🔄 [ROUTER_GUARD] [STORE_SESSION] Fallback config last_loja_id aceito → $loja (user=$currentEmail)',
            );
          }
        }
      }

      if (loja == null || loja.isEmpty) {
        logW('⚠️ [ROUTER_GUARD] Nenhuma loja encontrada, continuando...');
        return;
      }

      logD('✅ [STORE_SESSION] Loja ativa gravada: $loja');

      sessao.put('lojaId', loja);
      sessao.put('loja_id', loja);
      sessao.put('storeId', loja);
      sessao.put('store_id', loja);
      sessao.put('lojaIdAtual', loja);

      config.put('last_loja_id', loja);

      StoreResolverService.invalidate();
      await StoreResolverService.set(loja).timeout(const Duration(seconds: 2),
          onTimeout: () {
        logW('⚠️ [ROUTER_GUARD] Timeout ao persistir loja');
      });
    } catch (e, st) {
      logE('❌ [ROUTER_GUARD] Erro ao preparar loja (type=${e.runtimeType})', error: e, st: st);
    }
  }

  /// Validação em background para vendedor (já estamos na home)
  Future<void> _runVendedorValidationInBackground({
    required String uid,
    required String email,
    required Box sessao,
    required Box config,
  }) async {
    try {
      final userDocFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 3));
      final usuarioDocFuture = FirebaseFirestore.instance
          .collection('usuarios')
          .doc(email)
          .get()
          .timeout(const Duration(seconds: 3));
      final results =
          await Future.wait<DocumentSnapshot<Map<String, dynamic>>>([
        userDocFuture,
        usuarioDocFuture,
      ]);
      final userDoc = results[0];
      final usuarioDoc = results[1];

      String? vendedorStoreId;
      if (userDoc.exists) {
        final d = userDoc.data() ?? {};
        vendedorStoreId =
            (d['store_id'] ?? d['storeId'] ?? d['ownerStoreId'] ?? '')
                .toString()
                .trim();
      }
      if ((vendedorStoreId == null || vendedorStoreId.isEmpty) &&
          usuarioDoc.exists) {
        final d = usuarioDoc.data() ?? {};
        vendedorStoreId =
            (d['store_id'] ?? d['ownerStoreId'] ?? '').toString().trim();
      }
      if (vendedorStoreId != null && vendedorStoreId.isNotEmpty) {
        sessao.put('store_id', vendedorStoreId);
        sessao.put('storeId', vendedorStoreId);
      }
      await _bindActiveStore(sessao: sessao, config: config, isRoot: false);
      logD('✅ [ROUTER] Background: vendedor validado e loja preparada');
    } catch (e) {
      logW('⚠️ [ROUTER] Background vendedor (type=${e.runtimeType})');
    }
  }

  Future<void> _routeByRoleAndLoja(Box sessao) async {
    final role =
        (sessao.get('role') ?? sessao.get('tipo_usuario') ?? 'vendedor')
            .toString()
            .trim()
            .toLowerCase();

    final isRoot = (sessao.get('is_root') ?? false) == true;

    logD('🎯 [ROUTER] Role: $role, isRoot: $isRoot');

    if (isRoot || role == 'programador' || role == 'root') {
      logD('✅ [ROUTER] Root/Programador → /home');
      _goHomeOrRestore();
      return;
    }

    try {
      final lojaId = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);

      if (lojaId == null || lojaId.trim().isEmpty) {
        logW('⚠️ [ROUTER] Sem loja → /home (fallback)');
        _goHomeOrRestore();
        return;
      }

      logD('✅ [ROUTER] Loja OK → /home');
    } catch (e, st) {
      logE('❌ [ROUTER] Erro ao verificar loja (type=${e.runtimeType})', error: e, st: st);
    }

    _goHomeOrRestore();
  }

  void _setBusy(String msg) {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _msg = msg;
    });
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
  }

  /// Abre sempre na home. No APK o app não restaura a última tela (evita abrir em vendas/outra tela e voltar não levar à home).
  /// Na Web: se o usuário abriu um link direto (ex: /clientes), também vai para home.
  Future<void> _goHomeOrRestore() async {
    if (!mounted) return;
    logD(
      '[ROUTE_GUARD] _goHomeOrRestore path="${Uri.base.path}" kIsWeb=$kIsWeb mounted=$mounted',
    );
    // APK/mobile: sempre abrir na home para que o botão voltar leve à home ao sair de outras telas.
    if (!kIsWeb) {
      LastRouteObserver.getAndClearLastRoute();
      _go(_routeHome);
      return;
    }
    // Web: link direto não restaura; vai para home.
    final path = Uri.base.path.trim().toLowerCase();
    if (path.isNotEmpty && path != '/') {
      logD('🔄 [ROUTER] Web com path "$path" → indo para home');
      LastRouteObserver.getAndClearLastRoute();
      _go(_routeHome);
      return;
    }
    final lastRoute = await LastRouteObserver.getAndClearLastRoute();
    if (lastRoute != null && lastRoute.isNotEmpty && mounted) {
      logD('🔄 [ROUTER] Web: restaurando última tela: $lastRoute');
      // Coloca home na pilha primeiro para o botão voltar do navegador não deixar tela branca
      _go(_routeHome);
      if (!mounted) return;
      Navigator.pushNamed(context, lastRoute);
      return;
    }
    _go(_routeHome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      body: Center(
        child: _busy
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _msg,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
