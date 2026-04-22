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
import '../core/web_store_context_policy.dart';
import '../core/remote_config_keys.dart';
import '../models/user_profile.dart';
import '../services/planos_service.dart';
import '../services/user_profile_resolver.dart';
import '../services/remote_config_safe_service.dart';
import '../services/store_resolver_facade.dart';
import '../services/public_store_link_helper.dart';
import '../services/store_resolver_service.dart';
import '../utils/role_utils.dart'; // rootEmails + RoleUtils
import '../utils/last_route_observer.dart'; // ✅ Restaurar tela ao voltar do segundo plano

class AppStartRouter extends StatefulWidget {
  const AppStartRouter({super.key});

  @override
  State<AppStartRouter> createState() => _AppStartRouterState();
}

class _AppStartRouterState extends State<AppStartRouter> {
  bool _busy = true;
  bool _webLojaMissing = false;
  /// Firebase não inicializado (ex.: rede na subida) — mostrar retry em vez de loading infinito.
  bool _firebaseInitFailed = false;
  String _msg = 'Iniciando...';

  // ✅ CORREÇÃO: Usar const (lowercase)
  static const String _routeLogin = '/login';
  static const String _routePlanos = '/planos';
  static const String _routeHome = '/home';

  Set<String> _getRootAdminEmails() {
    if (!RemoteConfigSafeService.isFlagOn(rcEnableDynamicRootAdmins, fallback: false)) {
      return Set<String>.from(rootEmails);
    }
    final list = RemoteConfigSafeService.getStringListFromJson(
      rcRootAdminEmailsJson,
      fallback: rootEmails.toList(),
    );
    return list.isEmpty ? Set<String>.from(rootEmails) : list.toSet();
  }

  bool _isPaidSubscriptionPlanId(String raw) {
    final n = PlanosService.normalizePlanId(raw);
    return n == PlanId.proMonthly ||
        n == PlanId.proYearly ||
        n == PlanId.basicMonthly ||
        n == PlanId.intermediateMonthly;
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
    if (!mounted) return;
    setState(() {
      _firebaseInitFailed = true;
      _busy = false;
      _msg =
          'Conexão com Firebase indisponível. Verifique a rede e tente de novo.';
    });
  }

  Future<void> _run() async {
    try {
      if (mounted) {
        setState(() {
          _webLojaMissing = false;
          _firebaseInitFailed = false;
        });
      }
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
      await Hive.openBox('licenca');

      final sessao = Hive.box('sessao');
      final config = Hive.box('config');
      final licenca = Hive.box('licenca');

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

      // Antes de sobrescrever usuario_logado: validar atalhos Web (vendedor cache) contra principal antigo.
      final hivePrincipalBefore =
          (sessao.get('usuario_logado_email') ?? sessao.get('usuario_logado') ?? '')
              .toString()
              .trim()
              .toLowerCase();

      // Troca de conta no mesmo browser/dispositivo: Hive pode manter store_id da sessão anterior
      // e o fallback em _bindActiveStore reutiliza esse valor → mismatch com Firestore ("Loja não confirmada").
      if (hivePrincipalBefore.isNotEmpty && hivePrincipalBefore != email) {
        logD(
          '[BOOT-SESSION] Troca de conta ($hivePrincipalBefore → $email): limpando loja em cache',
        );
        sessao.delete('store_id');
        sessao.delete('storeId');
        sessao.delete('lojaId');
        sessao.delete('loja_id');
        sessao.delete('lojaIdAtual');
        config.delete('last_loja_id');
        StoreResolverService.invalidate();
      }

      sessao.put('usuario_logado', email);
      sessao.put('usuario_logado_email', email);

      final rootEmails = _getRootAdminEmails();
      final isRootEmail = rootEmails.contains(email);

      if (isRootEmail) {
        sessao.put('tipo_usuario', 'programador');
        sessao.put('is_root', true);
        sessao.put('role', 'programador');
      } else {
        sessao.put('is_root', false);
      }

      // ✅ ROOT: Web exige contexto de loja seguro (mesma política que admin); mobile mantém home + bind em background
      if (isRootEmail) {
        logD('🔑 [ROUTER] ROOT USER');
        if (kIsWeb) {
          await _bindActiveStore(sessao: sessao, config: config, isRoot: true);
          final ok = await _webResolveAndEvaluateStoreContext(sessao);
          if (!ok) {
            logW('[LOJA_ID] privileged_gate_block perfil=root_email');
            _setWebLojaMissingState();
            return;
          }
          logD('[LOJA_ID] privileged_gate_check perfil=root_email ok');
          _goHomeOrRestore();
          return;
        }
        _goHomeOrRestore();
        _bindActiveStore(sessao: sessao, config: config, isRoot: true);
        return;
      }

      // ✅ Atalho VENDEDOR: Web só com principal Hive alinhado ao Auth e store_id válido
      final cachedTipo =
          (sessao.get('tipo_usuario') ?? sessao.get('role') ?? '')
              .toString()
              .trim();
      final cachedStore = (sessao.get('store_id') ?? sessao.get('lojaId') ?? '')
          .toString()
          .trim();
      if (cachedTipo == 'vendedor' && cachedStore.isNotEmpty) {
        if (kIsWeb) {
          final principalOk =
              hivePrincipalBefore.isNotEmpty && hivePrincipalBefore == email;
          final storeOk = isValidForPublicLink(cachedStore);
          if (!principalOk || !storeOk) {
            logW(
              '[LOJA_ID] vendedor_cache_rejected motivo=${!principalOk ? "principal_mismatch" : "unsafe_store"}',
            );
          } else {
            logD('[LOJA_ID] privileged_gate_check perfil=vendedor_cache ok');
            _goHomeOrRestore();
            _runVendedorValidationInBackground(
                uid: uid, email: email, sessao: sessao, config: config);
            return;
          }
        } else {
          logD(
              '🚀 [ROUTER] Vendedor com sessão em cache → abrindo home e validando em background');
          _goHomeOrRestore();
          _runVendedorValidationInBackground(
              uid: uid, email: email, sessao: sessao, config: config);
          return;
        }
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
          if (kIsWeb) {
            final principal = (sessao.get('usuario_logado_email') ??
                    sessao.get('usuario_logado') ??
                    '')
                .toString()
                .trim()
                .toLowerCase();
            if (principal == email && isValidForPublicLink(cachedStore)) {
              vendedorStoreId = cachedStore;
              logD('📴 [ROUTER] Store da sessão (offline Web) validada');
            } else {
              logW('[LOJA_ID] vendedor_cache_rejected motivo=offline_session_unsafe');
            }
          } else {
            vendedorStoreId = cachedStore;
            logD('📴 [ROUTER] Store da sessão (offline)');
          }
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
      final licencaPlanRaw = (licenca.get('currentPlanId') ?? '').toString();
      final cachedPlanFromSession =
          (sessao.get('plan_plan_id') ?? '').toString();
      final cachedPlanNorm = PlanosService.normalizePlanId(
        licencaPlanRaw.isNotEmpty
            ? licencaPlanRaw
            : (cachedPlanFromSession.isNotEmpty
                ? cachedPlanFromSession
                : 'free_limited'),
      );
      final isPaidCached = cachedPlanNorm == PlanId.proMonthly ||
          cachedPlanNorm == PlanId.proYearly ||
          cachedPlanNorm == PlanId.lifetime ||
          cachedPlanNorm == PlanId.basicMonthly ||
          cachedPlanNorm == PlanId.intermediateMonthly;

      // Plano pago: não usar atalho de cache de 1h — sempre revalidar no Firestore.
      if (cacheValid && !isPaidCached) {
        logD('✅ [ROUTER] Plano em cache (não pago), entrando na home');
        final cachedPlan = cachedPlanNorm.isEmpty ? 'free_limited' : cachedPlanNorm;
        plan = PlanInfo(
          planId: cachedPlan,
          status: 'active',
          trialing: false,
          currentPeriodEnd: null,
          trialUsed: true,
          manualOverride: false,
          cancelAtPeriodEnd: false,
        );
      } else {
        plan = await planos
            .fetchCurrentPlan(uid: uid, email: email)
            .timeout(const Duration(seconds: 5), onTimeout: () {
          logW('⚠️ [ROUTER] Timeout ao buscar plano, continuando...');
          return null;
        });
        if (plan != null) {
          try {
            if (FirebaseAuth.instance.currentUser == null) {
              logW(
                '[PlanosAuthGate] reconcile ignorado: currentUser null após carregar plano',
              );
            } else {
              await planos
                  .reconcilePlanStateWithBackend()
                  .timeout(const Duration(seconds: 10));
            }
            final refreshed =
                await planos.fetchCurrentPlan(uid: uid, email: email);
            if (refreshed != null) plan = refreshed;
          } catch (e) {
            logW(
                '⚠️ [ROUTER] reconcilePlanStateWithBackend falhou (type=${e.runtimeType})');
          }
          // Após try/catch o analisador não promove plan; entrada era != null e só trocamos por refreshed.
          final p = plan!;
          sessao.put('plan_cache_until',
              DateTime.now().millisecondsSinceEpoch + 3600000); // 1h
          sessao.put('plan_expired', p.isExpired);
          sessao.put('plan_plan_id', p.planId);
          // Cache local apenas para boot/offline; Firestore segue canônico.
          licenca.put('currentPlanId', p.planId);
          licenca.put('expiresAt', p.currentPeriodEnd?.toIso8601String());
          licenca.put('ativado', !p.isExpired);
        }
      }

      if (plan == null) {
        // Offline ou timeout: cache só para planos não pagos (sem bypass de premium).
        final licencaPlan = (licenca.get('currentPlanId') ?? '').toString();
        final cachedPlanId = licencaPlan.isNotEmpty
            ? licencaPlan
            : (sessao.get('plan_plan_id') ?? 'free_limited').toString();
        final normalizedCached = PlanosService.normalizePlanId(cachedPlanId);
        final isPaidOffline = normalizedCached == PlanId.proMonthly ||
            normalizedCached == PlanId.proYearly ||
            normalizedCached == PlanId.lifetime ||
            normalizedCached == PlanId.basicMonthly ||
            normalizedCached == PlanId.intermediateMonthly;
        if (normalizedCached.isNotEmpty && !isPaidOffline) {
          logD('📴 [ROUTER] Usando plano em cache (offline/timeout): $normalizedCached');
          plan = PlanInfo(
            planId: normalizedCached,
            status: 'active',
            trialing: false,
            currentPeriodEnd: null,
            trialUsed: true,
            manualOverride: false,
            cancelAtPeriodEnd: false,
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
          final semDataOk = plan.planId == PlanId.freeLimited;
          if (plan.currentPeriodEnd == null && !semDataOk) {
            logW(
              '⚠️ [ROUTER] Plano sem currentPeriodEnd para ${plan.planId}; redirecionando para /planos sem deslogar',
            );
            if (!mounted) return;
            _go(_routePlanos);
            return;
          }

          if (plan.isExpired) {
            // Opção B: trial expirado → migra para free_limited (não bloqueia)
            if (plan.planId == PlanId.freeTrial90d ||
                plan.planId == PlanId.freeTrial30d) {
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
              // Plano pago vencido: backend → free_limited; fallback cliente; sem deslogar
              try {
                if (FirebaseAuth.instance.currentUser == null) {
                  logW(
                    '[PlanosAuthGate] reconcile (pago expirado) ignorado: currentUser null',
                  );
                } else {
                  await planos
                      .reconcilePlanStateWithBackend()
                      .timeout(const Duration(seconds: 10));
                }
                plan = await planos.fetchCurrentPlan(uid: uid, email: email);
              } catch (e) {
                logW(
                    '⚠️ [ROUTER] reconcile para plano pago expirado: ${e.runtimeType}');
              }
              if (plan != null &&
                  plan.isExpired &&
                  _isPaidSubscriptionPlanId(plan.planId)) {
                try {
                  await planos
                      .migrateToFreeLimited(uid: uid, email: email)
                      .timeout(const Duration(seconds: 4));
                  plan = await planos.fetchCurrentPlan(uid: uid, email: email);
                  logD(
                      '✅ [ROUTER] Plano pago expirado → free_limited (fallback)');
                } catch (e) {
                  logW(
                      '⚠️ [ROUTER] migrateToFreeLimited pago expirado: $e');
                }
              }
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
        final cachedUsuario = (sessao.get('usuario_logado_email') ??
                sessao.get('usuario_logado') ??
                '')
            .toString()
            .trim()
            .toLowerCase();

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

      if (kIsWeb &&
          loja != null &&
          loja.isNotEmpty &&
          !isValidForPublicLink(loja)) {
        logW('[LOJA_ID] router_bind_rejected motivo=store_id_formato_invalido');
        loja = null;
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

  String _sessionStoreId(Box sessao) {
    return (sessao.get('store_id') ??
            sessao.get('storeId') ??
            sessao.get('lojaId') ??
            '')
        .toString()
        .trim();
  }

  /// Web: resolve loja (router) e aplica a mesma política segura para qualquer perfil.
  Future<bool> _webResolveAndEvaluateStoreContext(Box sessao) async {
    String? resolvedId;
    var resolveThrew = false;
    try {
      resolvedId = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (e, st) {
      resolveThrew = true;
      logE('❌ [ROUTER] Erro ao verificar loja (type=${e.runtimeType})', error: e, st: st);
    }
    return _webEvaluateStoreContextSafe(
      sessao: sessao,
      resolvedId: resolvedId,
      resolveThrew: resolveThrew,
    );
  }

  /// Web: [resolveThrew] ou sessão/resolver incertos → false (nunca Home com contexto fantasma).
  bool _webEvaluateStoreContextSafe({
    required Box sessao,
    required String? resolvedId,
    required bool resolveThrew,
  }) {
    final r = WebStoreContextPolicyResult.evaluate(
      resolveThrew: resolveThrew,
      resolvedStoreId: resolvedId,
      sessionStoreId: _sessionStoreId(sessao),
    );
    if (r.allowed) {
      if (resolveThrew) {
        logD('[LOJA_ID] web resolve_exception sessão_ok');
      }
      return true;
    }
    logW(
      '[LOJA_ID] unsafe_store_context_rejected motivo=${r.rejectionMotivo}',
    );
    return false;
  }

  void _setWebLojaMissingState() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _webLojaMissing = true;
    });
  }

  Future<void> _routeByRoleAndLoja(Box sessao) async {
    final role =
        (sessao.get('role') ?? sessao.get('tipo_usuario') ?? 'vendedor')
            .toString()
            .trim()
            .toLowerCase();

    final isRoot = (sessao.get('is_root') ?? false) == true;

    logD('🎯 [ROUTER] Role: $role, isRoot: $isRoot');

    if (kIsWeb) {
      final ok = await _webResolveAndEvaluateStoreContext(sessao);
      if (!ok) {
        logW(
          '[LOJA_ID] privileged_gate_block role=$role isRoot=$isRoot motivo=web_store_unsafe',
        );
        _setWebLojaMissingState();
        return;
      }
      logD('[LOJA_ID] privileged_gate_check role=$role isRoot=$isRoot web_store_ok');
      _goHomeOrRestore();
      return;
    }

    // Mobile: programador/root seguem sem gate de loja (comportamento legado)
    if (isRoot || role == 'programador' || role == 'root') {
      logD('✅ [ROUTER] Root/Programador → /home');
      _goHomeOrRestore();
      return;
    }

    String? resolvedId;
    var resolveThrew = false;
    try {
      resolvedId = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (e, st) {
      resolveThrew = true;
      logE('❌ [ROUTER] Erro ao verificar loja (type=${e.runtimeType})', error: e, st: st);
    }

    if (resolveThrew) {
      _goHomeOrRestore();
      return;
    }

    final trimmed = resolvedId?.trim() ?? '';
    if (trimmed.isEmpty) {
      logW('⚠️ [ROUTER] Sem loja → /home (fallback)');
      _goHomeOrRestore();
      return;
    }

    logD('✅ [ROUTER] Loja OK → /home');
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

  /// No Web, evita zerar totalmente a pilha para que o botão voltar
  /// do navegador não "feche" o app ao entrar na home.
  void _goWebReplace(String route) {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, route);
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
      _goWebReplace(_routeHome);
      return;
    }
    final lastRoute = await LastRouteObserver.getAndClearLastRoute();
    if (lastRoute != null && lastRoute.isNotEmpty && mounted) {
      logD('🔄 [ROUTER] Web: restaurando última tela: $lastRoute');
      // Coloca home na pilha primeiro para o botão voltar do navegador não deixar tela branca
      _goWebReplace(_routeHome);
      if (!mounted) return;
      Navigator.pushNamed(context, lastRoute);
      return;
    }
    _goWebReplace(_routeHome);
  }

  @override
  Widget build(BuildContext context) {
    if (_firebaseInitFailed) {
      return Scaffold(
        backgroundColor: const Color(0xFF101010),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 48, color: Colors.red.shade200),
                    const SizedBox(height: 16),
                    Text(
                      'Sem conexão com o servidor',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _msg,
                      style: TextStyle(color: Colors.white.withOpacity(0.85)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _firebaseInitFailed = false;
                          _busy = true;
                          _msg = 'Tentando novamente...';
                        });
                        _run();
                      },
                      child: const Text('Tentar novamente'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _go(_routeLogin),
                      child: const Text('Voltar ao login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_webLojaMissing) {
      return Scaffold(
        backgroundColor: const Color(0xFF101010),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store_outlined, size: 48, color: Colors.amber.shade200),
                    const SizedBox(height: 16),
                    Text(
                      'Loja não confirmada',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Não foi possível carregar o contexto da sua loja com segurança neste navegador. '
                      'Verifique a conexão e tente novamente, ou saia e entre de novo.',
                      style: TextStyle(color: Colors.white.withOpacity(0.85)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _webLojaMissing = false;
                          _busy = true;
                          _msg = 'Tentando novamente...';
                        });
                        _run();
                      },
                      child: const Text('Tentar novamente'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _go(_routeLogin),
                      child: const Text('Voltar ao login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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
