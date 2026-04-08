// lib/services/planos_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

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

  const PlanInfo({
    required this.planId,
    required this.status,
    required this.trialing,
    required this.currentPeriodEnd,
    required this.trialUsed,
    required this.manualOverride,
  });

  bool get isLifetime => planId == PlanId.lifetime;
  /// Plano free limitado (após trial ou free sem upgrade)
  bool get isFreeLimited => planId == PlanId.freeLimited;
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
        return PlanId.freeTrial90d;
      case 'basic':
      case 'basic_monthly':
        return PlanId.basicMonthly;
      case 'intermediate':
      case 'intermediate_monthly':
        return PlanId.intermediateMonthly;
      case 'free_limited':
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
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('⚠️ Erro ao espelhar plano no Firestore (modo offline) (type=${e.runtimeType})');
    }
  }

  /// Lê o plano atual (considera manualOverride primeiro)
  Future<PlanInfo?> fetchCurrentPlan({
    required String uid,
    required String email,
  }) async {
    // ✅ ROOT USERS tem plano lifetime automático
    const rootEmails = {'masterpalm26@gmail.com', 'masterpalm@gmail.com', 'admin@masterpalm.com'};
    if (rootEmails.contains(email.toLowerCase())) {
      return const PlanInfo(
        planId: 'lifetime',
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: false,
        manualOverride: true,
      );
    }

    try {
      // 1) Verificar na collection 'users/{uid}'
      final doc = await _userRef(uid).get().timeout(const Duration(seconds: 2));

      // 2) Verificar também na collection 'usuarios/{email}' (fallback legado)
      Map<String, dynamic>? usuarioData;
      try {
        final usuarioDoc = await _db.collection('usuarios').doc(email).get()
            .timeout(const Duration(seconds: 2));
        if (usuarioDoc.exists) usuarioData = usuarioDoc.data();
      } catch (_) {}

      if (doc.exists) {
        final d = doc.data() ?? const <String, dynamic>{};
        final mo = (d['manualOverride'] is Map) ? (d['manualOverride'] as Map) : null;
        final moEnabled = mo != null && (mo['enabled'] == true);

        // Fonte canônica
        String planId = normalizePlanId(d['currentPlanId']?.toString());
        String status = (d['status'] ?? 'active').toString();
        bool trialing = (d['trialing'] ?? false) == true;
        DateTime? end = _parseEnd(d['currentPeriodEnd']);
        bool trialUsed = (d['trialUsed'] ?? false) == true;
        // users/{uid} é canônico; legado em users.plan* não é mais lido.
        if (status.trim().isEmpty) status = 'active';

        if (moEnabled) {
          planId = normalizePlanId((mo['planId'] ?? PlanId.lifetime).toString());
          status = 'active';
          trialing = false;
          end = null; // override manual prevalece
        }

        if (planId.isNotEmpty) {
          return PlanInfo(
            planId: planId,
            status: status,
            trialing: trialing,
            currentPeriodEnd: end,
            trialUsed: trialUsed,
            manualOverride: moEnabled,
          );
        }
      }

      // Fallback legado em usuarios/{email}
      if (usuarioData != null && usuarioData['planoAtivo'] == true) {
        final planoId = normalizePlanId((usuarioData['planoId'] ?? '').toString());
        if (planoId.isNotEmpty) {
          return PlanInfo(
            planId: planoId,
            status: 'active',
            trialing: false,
            currentPeriodEnd: _parseEnd(usuarioData['currentPeriodEnd']),
            trialUsed: true,
            manualOverride: usuarioData['manualOverride'] == true,
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
    // Se for lifetime, currentPeriodEnd fica null
    final override = {
      'enabled': true,
      'planId': planId,
      'grantedBy': grantedByEmail,
      'grantedAt': FieldValue.serverTimestamp(),
    };

    await _mirror(
      uid: targetUid,
      email: targetEmail,
      planId: planId,
      status: 'active',
      trialing: false,
      currentPeriodEnd: planId == PlanId.lifetime
          ? null
          : DateTime.now().add(const Duration(days: 3650)), // fallback longo
      manualOverride: override,
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
