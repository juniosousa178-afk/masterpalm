// lib/services/planos_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../utils/role_utils.dart';

class PlanId {
  static const String freeTrial30d = 'free_trial_30d';
  static const String freeTrial90d = 'free_trial_90d';
  static const String freeLimited = 'free_limited'; // Após 90 dias: plano limitado (Opção B)
  static const String basicMonthly = 'basic_monthly';
  static const String intermediateMonthly = 'intermediate_monthly';
  static const String proMonthly = 'pro_monthly';
  static const String proYearly = 'pro_yearly';
  static const String lifetime = 'lifetime';
}

class PlanInfo {
  final String planId;
  final String status;
  final bool trialing;
  final DateTime? currentPeriodEnd;
  final bool trialUsed;
  final bool manualOverride;
  /// Renovação cancelada no fim do período (fonte: users/{uid}.cancelAtPeriodEnd no backend).
  final bool cancelAtPeriodEnd;

  const PlanInfo({
    required this.planId,
    required this.status,
    required this.trialing,
    required this.currentPeriodEnd,
    required this.trialUsed,
    required this.manualOverride,
    this.cancelAtPeriodEnd = false,
  });

  bool get isLifetime => planId == PlanId.lifetime;
  /// Plano free limitado (após trial ou free sem upgrade)
  bool get isFreeLimited => planId == PlanId.freeLimited;
  /// Assinatura paga mensal/anual (Básico, Intermediário, Pro) — não inclui trial nem lifetime.
  bool get isPaidSubscription {
    return planId == PlanId.basicMonthly ||
        planId == PlanId.intermediateMonthly ||
        planId == PlanId.proMonthly ||
        planId == PlanId.proYearly;
  }
  /// Tem restrições de limite (produtos, vendas, clientes, etc.)
  bool get hasLimits => isFreeLimited;
  bool get isActive {
    if (isLifetime) return true;
    // Free limitado não tem data de término; permanece utilizável com limites numéricos.
    if (isFreeLimited) {
      return status == 'active' || status == 'trialing';
    }
    if (status != 'active' && status != 'trialing') return false;
    if (currentPeriodEnd == null) return false;
    return currentPeriodEnd!.isAfter(DateTime.now());
  }

  bool get isExpired {
    if (isLifetime) return false;
    if (planId == PlanId.freeLimited) return false; // free_limited nunca expira (só limites)
    if (currentPeriodEnd == null) return true;
    return currentPeriodEnd!.isBefore(DateTime.now());
  }

  int? get daysLeft {
    if (isLifetime) return null;
    if (currentPeriodEnd == null) return 0;
    final d = currentPeriodEnd!.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }
}

class PlanosService {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _subsCol(String uid) =>
      _userRef(uid).collection('subscriptions');

  DateTime? _parseEnd(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return null;
  }

  static String normalizePlanId(String? raw) {
    final p = (raw ?? '').trim().toLowerCase();
    switch (p) {
      case 'mensal':
      case 'pro_monthly':
        return PlanId.proMonthly;
      case 'anual':
      case 'pro_yearly':
        return PlanId.proYearly;
      case 'trial_30d':
      case 'free_trial_30d':
        return PlanId.freeTrial30d;
      case 'trial_90d':
      case 'free_trial_90d':
      case 'trial':
      case 'free_trial':
        return PlanId.freeTrial90d;
      case 'basic':
      case 'basic_monthly':
        return PlanId.basicMonthly;
      case 'intermediate':
      case 'intermediate_monthly':
        return PlanId.intermediateMonthly;
      case 'free_limited':
      case 'freelight':
        return PlanId.freeLimited;
      case 'lifetime':
        return PlanId.lifetime;
      default:
        return p;
    }
  }

  Future<void> _mirror({
    required String uid,
    required String email,
    required String planId,
    required String status,
    required bool trialing,
    DateTime? currentPeriodEnd,
    bool? trialUsed,
    DateTime? trialUsedAt,
    Map<String, dynamic>? manualOverride,
    bool? cancelAtPeriodEnd,
  }) async {
    try {
      await _userRef(uid).set({
        'email': email,
        'currentPlanId': planId,
        'status': status,
        'trialing': trialing,
        'currentPeriodEnd':
            currentPeriodEnd != null ? Timestamp.fromDate(currentPeriodEnd) : null,
        if (trialUsed != null) 'trialUsed': trialUsed,
        if (trialUsedAt != null) 'trialUsedAt': Timestamp.fromDate(trialUsedAt),
        if (manualOverride != null) 'manualOverride': manualOverride,
        if (cancelAtPeriodEnd != null) 'cancelAtPeriodEnd': cancelAtPeriodEnd,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('⚠️ Erro ao espelhar plano no Firestore (modo offline) (type=${e.runtimeType})');
    }
  }

  /// Precedência de leitura (alto → baixo): root/programador → manualOverride em
  /// users/{uid} → demais campos em users/{uid} → usuarios/{email} só se users/{uid}
  /// não existir → (Hive não promove plano aqui).
  Future<PlanInfo?> fetchCurrentPlan({
    required String uid,
    required String email,
  }) async {
    // 1) Root/programador — mesma lista que backend (rootAccounts / RoleUtils)
    if (RoleUtils.isRootEmail(email)) {
      return const PlanInfo(
        planId: 'lifetime',
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: false,
        manualOverride: true,
        cancelAtPeriodEnd: false,
      );
    }

    try {
      final doc = await _userRef(uid).get().timeout(const Duration(seconds: 2));

      if (doc.exists) {
        final d = doc.data() ?? const <String, dynamic>{};
        final mo = (d['manualOverride'] is Map) ? (d['manualOverride'] as Map) : null;
        final moEnabled = mo != null && (mo['enabled'] == true);

        // Fonte canônica: users/{uid}
        final rawCurrent = d['currentPlanId']?.toString() ?? '';
        String planId = normalizePlanId(rawCurrent);
        if (rawCurrent.trim().isNotEmpty &&
            rawCurrent.trim().toLowerCase() != planId) {
          debugPrint(
            '[PlanosCompat] currentPlanId legado normalizado -> $planId',
          );
        }
        String status = (d['status'] ?? 'active').toString();
        bool trialing = (d['trialing'] ?? false) == true;
        DateTime? end = _parseEnd(d['currentPeriodEnd']);
        bool trialUsed = (d['trialUsed'] ?? false) == true;
        final cancelAtPeriodEnd =
            (d['cancelAtPeriodEnd'] ?? d['cancel_at_period_end']) == true;
        if (status.trim().isEmpty) status = 'active';

        if (moEnabled) {
          final rawMo = (mo['planId'] ?? PlanId.lifetime).toString();
          planId = normalizePlanId(rawMo);
          status = 'active';
          trialing = false;
          end = null;
          debugPrint('[PlanosCompat] manualOverride ativo planId=$planId');
        }

        if (planId.isNotEmpty) {
          return PlanInfo(
            planId: planId,
            status: status,
            trialing: trialing,
            currentPeriodEnd: end,
            trialUsed: trialUsed,
            manualOverride: moEnabled,
            cancelAtPeriodEnd: moEnabled ? false : cancelAtPeriodEnd,
          );
        }
        return null;
      }

      // 2) Fallback legado: só quando users/{uid} não existe (nunca sobrescreve doc canônico)
      Map<String, dynamic>? usuarioData;
      try {
        final usuarioDoc = await _db.collection('usuarios').doc(email).get()
            .timeout(const Duration(seconds: 2));
        if (usuarioDoc.exists) usuarioData = usuarioDoc.data();
      } catch (_) {}

      if (usuarioData != null && usuarioData['planoAtivo'] == true) {
        final rawLegado = (usuarioData['planoId'] ?? '').toString();
        final planoId = normalizePlanId(rawLegado);
        if (planoId.isNotEmpty) {
          if (rawLegado.trim().isNotEmpty &&
              rawLegado.trim().toLowerCase() != planoId) {
            debugPrint(
              '[PlanosCompat] usuarios/planoId legado normalizado -> $planoId',
            );
          }
          return PlanInfo(
            planId: planoId,
            status: 'active',
            trialing: false,
            currentPeriodEnd: _parseEnd(usuarioData['currentPeriodEnd']),
            trialUsed: true,
            manualOverride: usuarioData['manualOverride'] == true,
            cancelAtPeriodEnd: false,
          );
        }
      }
      return null;
    } catch (e) {
      // Sem rede / erro: não inventar plano — a UI deve reconsultar o Firestore.
      debugPrint('⚠️ Erro ao buscar plano (type=${e.runtimeType})');
      return null;
    }
  }

  /// Garante trial (30 dias — novo padrão) se ainda não tem plano e ainda não usou trial.
  Future<PlanInfo?> ensureTrial90dIfAllowed({
    required String uid,
    required String email,
  }) async {
    final current = await fetchCurrentPlan(uid: uid, email: email);
    if (current != null) return current;

    // se não existe user doc ainda, cria e ativa trial
    await activateFreeTrialViaBackend(uid: uid, email: email);
    return fetchCurrentPlan(uid: uid, email: email);
  }

  /// Ativa trial via Cloud Function (30 dias, `free_trial_30d`; legado 90d permanece no Firestore para contas antigas).
  /// Escrita apenas no backend; cliente não grava subscriptions.
  Future<void> activateFreeTrialViaBackend({
    required String uid,
    required String email,
  }) async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('activateUserTrial90d');
    try {
      final result = await callable.call(<String, dynamic>{});
      final map = result.data;
      if (map is Map && map['ok'] == true) {
        debugPrint('✅ [PlanosTrial] Trial ativado via CF uid=$uid');
        return;
      }
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        throw Exception('TRIAL_ALREADY_USED');
      }
      debugPrint('⚠️ [PlanosTrial] CF erro ${e.code}: ${e.message}');
      rethrow;
    }
  }

  /// Chama [ensureUserPlan] no backend — aplica vencimento de plano pago → free_limited e consistência.
  Future<void> reconcilePlanStateWithBackend() async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('ensureUserPlan');
    try {
      await callable.call(<String, dynamic>{});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('⚠️ [Planos] ensureUserPlan ${e.code}: ${e.message}');
      rethrow;
    }
  }

  /// Cancela só a renovação; o acesso permanece até [currentPeriodEnd] (Cloud Function).
  Future<void> cancelRenewalAtPeriodEndViaBackend() async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('cancelPlanRenewalAtPeriodEnd');
    try {
      final result = await callable.call(<String, dynamic>{});
      final map = result.data;
      if (map is Map && map['ok'] == true) return;
      throw Exception('Resposta inválida ao cancelar renovação.');
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Reativa a cobrança recorrente antes do fim do período atual.
  Future<void> reactivateRenewalViaBackend() async {
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('reactivatePlanRenewal');
    try {
      final result = await callable.call(<String, dynamic>{});
      final map = result.data;
      if (map is Map && map['ok'] == true) return;
      throw Exception('Resposta inválida ao reativar renovação.');
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Marca plano pago como ativo (pós webhook)
  Future<void> markPaidActive({
    required String uid,
    required String email,
    required String planId, // pro_monthly | pro_yearly
    required DateTime currentPeriodEnd,
    String? subId,
  }) async {
    final id = subId ?? _subsCol(uid).doc().id;

    await _subsCol(uid).doc(id).set({
      'planId': planId,
      'status': 'active',
      'trialing': false,
      'currentPeriodEnd': Timestamp.fromDate(currentPeriodEnd),
      'updatedAt': FieldValue.serverTimestamp(),
      'kind': 'paid',
    }, SetOptions(merge: true));

    await _mirror(
      uid: uid,
      email: email,
      planId: planId,
      status: 'active',
      trialing: false,
      currentPeriodEnd: currentPeriodEnd,
      cancelAtPeriodEnd: false,
    );
  }

  /// Migra free_trial_90d expirado para free_limited (Opção B: não bloqueia, aplica limites)
  Future<void> migrateToFreeLimited({
    required String uid,
    required String email,
  }) async {
    await _mirror(
      uid: uid,
      email: email,
      planId: PlanId.freeLimited,
      status: 'active',
      trialing: false,
      currentPeriodEnd: null, // sem data de expiração
      trialUsed: true,
      manualOverride: null,
      cancelAtPeriodEnd: false,
    );
    debugPrint('✅ [PLANOS] Migrado para free_limited (plano limitado)');
  }

  /// Se expirou, marca expired (opcional). NÃO usado para free_trial_90d (migra para free_limited)
  Future<void> markExpiredIfNeeded({
    required String uid,
    required String email,
  }) async {
    final info = await fetchCurrentPlan(uid: uid, email: email);
    if (info == null) return;
    if (info.isLifetime) return;
    if (!info.isExpired) return;

    await _mirror(
      uid: uid,
      email: email,
      planId: info.planId,
      status: 'expired',
      trialing: false,
      currentPeriodEnd: info.currentPeriodEnd,
    );
  }

  /// ROOT: liberar plano manual (lifetime ou outro)
  Future<void> grantManualOverride({
    required String targetUid,
    required String targetEmail,
    required String planId, // lifetime | pro_monthly | pro_yearly
    required String grantedByEmail, // masterpalm26@gmail.com
  }) async {
    final canonical = normalizePlanId(planId);
    if (planId.trim().toLowerCase() != canonical) {
      debugPrint(
        '[PlanosCompat] grantManualOverride entrada normalizada -> $canonical',
      );
    }
    // Se for lifetime, currentPeriodEnd fica null
    final override = {
      'enabled': true,
      'planId': canonical,
      'grantedBy': grantedByEmail,
      'grantedAt': FieldValue.serverTimestamp(),
    };

    await _mirror(
      uid: targetUid,
      email: targetEmail,
      planId: canonical,
      status: 'active',
      trialing: false,
      currentPeriodEnd: canonical == PlanId.lifetime
          ? null
          : DateTime.now().add(const Duration(days: 3650)), // fallback longo
      manualOverride: override,
      cancelAtPeriodEnd: false,
    );
  }

  /// ROOT: remover override
  Future<void> revokeManualOverride({
    required String targetUid,
  }) async {
    await _userRef(targetUid).set({
      'manualOverride': {'enabled': false},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
