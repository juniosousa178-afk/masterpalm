// lib/services/checkout_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, visibleForTesting;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';

import '../core/master_plan_access_models.dart';
import 'checkout_url_opener.dart';
import 'license_manager.dart';
import 'planos_service.dart';
import 'remote_config_service.dart';

/// Resultado mínimo da UX de troca de plano (ex.: deep link / retorno do checkout MP).
enum PlanChangeCallOutcome {
  opened,
  alreadyActive,
}

enum CheckoutFlowType {
  oneTime,
  recurringCreate,
  planChange,
  alreadyActive,
  pendingConflict,
  unknownState,
}

class CheckoutLaunchResult {
  final CheckoutFlowType flowType;
  final Uri? checkoutUrl;
  final String? pendingChangeId;
  final String? message;
  final bool opened;

  const CheckoutLaunchResult({
    required this.flowType,
    this.checkoutUrl,
    this.pendingChangeId,
    this.message,
    this.opened = false,
  });
}

class CheckoutRoutingSnapshot {
  final PlanInfo? plan;
  final EffectivePlanAccessDto? access;
  final bool unknown;

  const CheckoutRoutingSnapshot({
    this.plan,
    this.access,
    this.unknown = false,
  });

  factory CheckoutRoutingSnapshot.unknown() =>
      const CheckoutRoutingSnapshot(unknown: true);
}

enum CheckoutUpgradeDecisionKind {
  planChange,
  oneTimeOrCreate,
  alreadyActive,
  pendingTargetConflict,
  unknownState,
}

class CheckoutUpgradeDecision {
  final CheckoutUpgradeDecisionKind kind;
  final String? message;

  const CheckoutUpgradeDecision(this.kind, {this.message});
}

const _kPaidCanonicalPlanIds = {
  'basic_monthly',
  'intermediate_monthly',
  'pro_monthly',
  'pro_yearly',
};

const _kP1eFreeEligiblePlanIds = {
  'free_limited',
  'free_trial_30d',
  'free_trial_90d',
};

/// Target Pro (mensal/anual) for P1E Free → recurring create. Not Basic/Intermediate.
bool isP1eProTarget(String? raw) {
  final t = normalizeCheckoutPlanId(raw);
  return t == 'pro_monthly' || t == 'pro_yearly';
}

bool _normalizedIsPaidPlan(String? raw) {
  final n = (raw ?? '').trim();
  if (n.isEmpty) return false;
  return _kPaidCanonicalPlanIds.contains(normalizeCheckoutPlanId(n));
}

/// P1E Free eligibility (027). Never treat Basic/paid/lifetime/provider-id as Free.
bool isP1eFreeEligible(CheckoutRoutingSnapshot snapshot) {
  if (snapshot.unknown) return false;
  final plan = snapshot.plan;
  final providerId = plan?.providerSubscriptionId?.trim() ?? '';
  if (providerId.isNotEmpty) return false;
  if (snapshot.access?.subscription.hasMaskedSubscriptionId == true) {
    return false;
  }
  if (plan?.isLifetime == true) return false;

  final fromPlan = (plan?.planId ?? '').trim();
  final fromDto = (snapshot.access?.contractedPlanId ?? '').trim();
  if (_normalizedIsPaidPlan(fromPlan) || _normalizedIsPaidPlan(fromDto)) {
    return false;
  }

  final ids = <String>{};
  if (fromPlan.isNotEmpty) ids.add(normalizeCheckoutPlanId(fromPlan));
  if (fromDto.isNotEmpty) ids.add(normalizeCheckoutPlanId(fromDto));
  if (ids.contains('lifetime')) return false;
  if (ids.isEmpty) return true;
  return ids.every(_kP1eFreeEligiblePlanIds.contains);
}

String normalizeCheckoutPlanId(String? raw) {
  final p = (raw ?? '').trim().toLowerCase();
  switch (p) {
    case 'mensal':
    case 'pro_monthly':
      return 'pro_monthly';
    case 'anual':
    case 'pro_yearly':
      return 'pro_yearly';
    case 'basic':
    case 'basic_monthly':
      return 'basic_monthly';
    case 'intermediate':
    case 'intermediate_monthly':
      return 'intermediate_monthly';
    case 'trial_90d':
    case 'free_trial_90d':
      return 'free_trial_90d';
    case 'trial_30d':
    case 'free_trial_30d':
      return 'free_trial_30d';
    default:
      return p;
  }
}

bool _isPaidCanonicalPlanId(String? id) {
  final n = (id ?? '').trim().toLowerCase();
  return _kPaidCanonicalPlanIds.contains(n);
}

String? _contractedPlanIdFromSnapshot(CheckoutRoutingSnapshot snap) {
  final fromPlan = snap.plan?.planId.trim();
  if (fromPlan != null && fromPlan.isNotEmpty) return fromPlan;
  final fromDto = snap.access?.contractedPlanId?.trim();
  if (fromDto != null && fromDto.isNotEmpty) return fromDto;
  return null;
}

bool snapshotHasActiveRecurringSubscription(CheckoutRoutingSnapshot snap) {
  final p = snap.plan;
  if (p != null) {
    if (p.manualOverride) return false;
    if (!p.isPaidSubscription || !p.isActive) return false;
    final billingRecurring =
        (p.billingMode ?? '').trim().toLowerCase() == 'recurring' ||
            p.usesMercadoRecurringPlanBilling;
    final hasSub = (p.providerSubscriptionId?.trim().isNotEmpty ?? false) ||
        snap.access?.subscription.hasMaskedSubscriptionId == true;
    return billingRecurring && hasSub;
  }
  final dto = snap.access;
  if (dto == null) return false;
  if (!_isPaidCanonicalPlanId(dto.contractedPlanId)) return false;
  final status = (dto.effectiveStatus ?? '').trim().toLowerCase();
  final activeLike =
      status.isEmpty || status == 'active' || status == 'trialing';
  if (!activeLike) return false;
  if (dto.renewal.active == false &&
      dto.accessSource != 'paid_subscription' &&
      !dto.subscription.hasMaskedSubscriptionId) {
    return false;
  }
  return dto.subscription.hasMaskedSubscriptionId ||
      dto.accessSource == 'paid_subscription';
}

/// Decisão de routing: nunca usa só `_plan` em memória da UI.
CheckoutUpgradeDecision decideCheckoutUpgradeRoute({
  required CheckoutRoutingSnapshot snapshot,
  required String targetCanonical,
}) {
  if (snapshot.unknown) {
    return const CheckoutUpgradeDecision(
      CheckoutUpgradeDecisionKind.unknownState,
      message:
          'Não foi possível confirmar o seu plano atual. Atualize e tente de novo.',
    );
  }

  final target = normalizeCheckoutPlanId(targetCanonical);
  final plan = snapshot.plan;

  if (plan != null && plan.hasPendingChangeTo(target)) {
    return CheckoutUpgradeDecision(
      CheckoutUpgradeDecisionKind.pendingTargetConflict,
      message:
          'Já existe uma alteração para ${plan.pendingPlanChangeToPlanId} a aguardar pagamento.',
    );
  }

  final contracted = _contractedPlanIdFromSnapshot(snapshot);
  final contractedNorm = contracted == null
      ? null
      : normalizeCheckoutPlanId(contracted);
  final recurring = snapshotHasActiveRecurringSubscription(snapshot);

  if (recurring && contractedNorm != null && contractedNorm == target) {
    return const CheckoutUpgradeDecision(
      CheckoutUpgradeDecisionKind.alreadyActive,
      message: 'Você já está com este plano ativo.',
    );
  }

  if (recurring && contractedNorm != null && contractedNorm != target) {
    return const CheckoutUpgradeDecision(CheckoutUpgradeDecisionKind.planChange);
  }

  if (_isPaidCanonicalPlanId(contractedNorm) &&
      contractedNorm == target &&
      (plan?.isActive == true || snapshot.access != null)) {
    return const CheckoutUpgradeDecision(
      CheckoutUpgradeDecisionKind.alreadyActive,
      message: 'Você já está com este plano ativo.',
    );
  }

  return const CheckoutUpgradeDecision(
    CheckoutUpgradeDecisionKind.oneTimeOrCreate,
  );
}

bool _isPlanChangeFallbackToOneTime(Object e) {
  if (e is FirebaseFunctionsException) {
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();
    if (code == 'failed-precondition' &&
        (msg.contains('recurring_plan_billing_disabled') ||
            msg.contains('use assinatura comum'))) {
      return true;
    }
  }
  final s = e.toString().toLowerCase();
  if (s.contains('recurring_plan_billing_disabled')) return true;
  if (s.contains('use assinatura comum')) return true;
  return false;
}

/// Orquestrador testável: serviço devolve checkout; opener navega.
class CheckoutPlanCoordinator {
  CheckoutPlanCoordinator({
    required this.resolveSnapshot,
    required this.callPlanChange,
    required this.openNewCheckout,
    required this.opener,
    this.openRecurringCreate,
  });

  final Future<CheckoutRoutingSnapshot> Function() resolveSnapshot;
  final Future<Map<String, dynamic>> Function(String planApi) callPlanChange;
  final Future<CheckoutLaunchResult> Function(String planApi) openNewCheckout;
  /// P1E Free → Pro. Production wires [CheckoutService._abrirCheckoutPlanoRecorrente].
  final Future<CheckoutLaunchResult> Function(String planApi)? openRecurringCreate;
  final CheckoutUrlOpener opener;

  int planChangeCallCount = 0;
  int newCheckoutCallCount = 0;
  int recurringCreateCallCount = 0;

  Future<CheckoutLaunchResult> run({required String planoId}) async {
    final snapshot = await resolveSnapshot();
    final target = normalizeCheckoutPlanId(planoId);
    final decision = decideCheckoutUpgradeRoute(
      snapshot: snapshot,
      targetCanonical: target,
    );

    switch (decision.kind) {
      case CheckoutUpgradeDecisionKind.unknownState:
        throw Exception(
          decision.message ??
              'Não foi possível confirmar o seu plano atual. Atualize e tente de novo.',
        );
      case CheckoutUpgradeDecisionKind.alreadyActive:
        return CheckoutLaunchResult(
          flowType: CheckoutFlowType.alreadyActive,
          message: decision.message ?? 'Você já está com este plano ativo.',
        );
      case CheckoutUpgradeDecisionKind.pendingTargetConflict:
        throw Exception(
          decision.message ??
              'Já existe uma alteração para este plano a aguardar pagamento.',
        );
      case CheckoutUpgradeDecisionKind.oneTimeOrCreate:
        if (openRecurringCreate != null &&
            isP1eFreeEligible(snapshot) &&
            isP1eProTarget(target)) {
          recurringCreateCallCount++;
          return openRecurringCreate!(target);
        }
        newCheckoutCallCount++;
        return openNewCheckout(target);
      case CheckoutUpgradeDecisionKind.planChange:
        planChangeCallCount++;
        try {
          final map = await callPlanChange(target);
          if (map['alreadyActive'] == true) {
            return CheckoutLaunchResult(
              flowType: CheckoutFlowType.alreadyActive,
              message: map['message']?.toString() ??
                  'Você já está com este plano ativo.',
            );
          }
          final initPoint = map['initPoint']?.toString();
          final uri = validateCheckoutHttpsUri(initPoint);
          await opener.open(uri);
          return CheckoutLaunchResult(
            flowType: CheckoutFlowType.planChange,
            checkoutUrl: uri,
            pendingChangeId: map['changeId']?.toString(),
            opened: true,
          );
        } catch (e) {
          if (e is CheckoutUrlValidationException) rethrow;
          if (_isPlanChangeFallbackToOneTime(e)) {
            newCheckoutCallCount++;
            return openNewCheckout(target);
          }
          rethrow;
        }
    }
  }
}

/// POST em [planCreatePreference]: credencial MP só no backend (Secret Manager).
/// No Web: [reload] + [getIdToken(true)] antes do POST; em 401, pausa curta e repete uma vez
/// com [currentUser] atualizado (evita referência de [User] stale).
Future<http.Response> _postPlanCreatePreference({
  required Uri url,
  required Map<String, dynamic> body,
}) async {
  Future<http.Response> attempt({required int attemptNumber}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }
    if (kIsWeb) {
      try {
        await user.reload();
      } catch (e) {
        debugPrint(
          '⚠️ [CheckoutPlano] user.reload (tentativa $attemptNumber): $e',
        );
      }
    }
    final idToken = await user.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw Exception('Sessão inválida. Faça login novamente.');
    }
    return http
        .post(
          url,
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));
  }

  debugPrint(
    '[CheckoutPlano] planCreatePreference — MP no servidor (não usa app_config/master)',
  );
  var resp = await attempt(attemptNumber: 1);
  if (resp.statusCode == 401) {
    debugPrint(
      '⚠️ [CheckoutPlano] planCreatePreference 401 na 1ª tentativa (Firebase ID token) — retry',
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    resp = await attempt(attemptNumber: 2);
    if (resp.statusCode == 401) {
      debugPrint(
        '❌ [CheckoutPlano] planCreatePreference 401 após retry — sessão recusada pelo servidor',
      );
    }
  }
  return resp;
}

/// No Web, [planCreatePreferenceCall] usa auth do SDK (evita 401 quando o browser não envia Bearer ao HTTP).
Future<Map<String, dynamic>?> _tryPlanCreatePreferenceCallOnWeb({
  required String plan,
  required String installationId,
}) async {
  if (!kIsWeb) return null;
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      await user.reload();
    } catch (e) {
      debugPrint('[PlanosAuthDiag] callable reload: $e');
    }
    final idTok = await user.getIdToken(true);
    debugPrint(
      '[PlanosAuthDiag] planCreatePreferenceCall plan=$plan '
      'idTokenNonEmpty=${idTok != null && idTok.isNotEmpty}',
    );
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable('planCreatePreferenceCall');
    final result = await callable.call(<String, dynamic>{
      'plan': plan,
      if (installationId.isNotEmpty) 'installationId': installationId,
    });
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  } on FirebaseFunctionsException catch (e) {
    final m = e.message ?? '';
    debugPrint(
      '[PlanosAuthDiag] planCreatePreferenceCall code=${e.code} '
      'message=${m.length > 120 ? m.substring(0, 120) : m}',
    );
    return null;
  } catch (e) {
    debugPrint('[PlanosAuthDiag] planCreatePreferenceCall erro: $e');
    return null;
  }
}

/// Checkout de planos: preferência criada **somente** no backend (token MP fora do app).
class CheckoutService {
  /// Callable exportado em `functions/index.js` para assinatura recorrente inicial.
  static const String planSubscriptionCallableName = 'createPlanSubscription';

  /// Callable exportado em `functions/index.js` para troca de plano recorrente.
  static const String planChangeSubscriptionCallableName =
      'createPlanChangeSubscription';

  static bool _isCriticalRecurringError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('mp platform token não configurado') ||
        s.contains('mp token não configurado') ||
        s.contains('token not configured')) {
      return true;
    }
    if (s.contains('usuário não autenticado') ||
        s.contains('unauthenticated') ||
        s.contains('faça login')) {
      return true;
    }
    return false;
  }

  static bool _shouldFallbackToOneTimeRecurringError(Object e) {
    if (_isCriticalRecurringError(e)) return false;
    if (e is FirebaseFunctionsException) {
      final code = e.code.toLowerCase();
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('recurring_plan_billing_disabled')) return true;
      if (code == 'invalid-argument' ||
          code == 'failed-precondition' ||
          code == 'deadline-exceeded' ||
          code == 'unavailable' ||
          code == 'internal' ||
          code == 'unknown') {
        return true;
      }
    }
    final s = e.toString().toLowerCase();
    if (s.contains('initpoint') ||
        s.contains('preapprovalid') ||
        s.contains('resposta inválida') ||
        s.contains('timeout') ||
        s.contains('network') ||
        s.contains('socket') ||
        s.contains('http 400') ||
        s.contains('http 401') ||
        s.contains('http 403') ||
        s.contains('http 500') ||
        s.contains('payload') ||
        s.contains('valida')) {
      return true;
    }
    return false;
  }

  static String _normalizePlanId(String? raw) => normalizeCheckoutPlanId(raw);

  /// Corpo `plan` aceito por [planCreatePreference] (Cloud Function).
  static String _apiPlanFromCanonical(String canonical) {
    switch (canonical) {
      case 'pro_yearly':
        return 'anual';
      case 'pro_monthly':
        return 'mensal';
      case 'basic_monthly':
      case 'intermediate_monthly':
        return canonical;
      default:
        return canonical;
    }
  }

  @visibleForTesting
  static CheckoutUrlOpener urlOpener = PlatformCheckoutUrlOpener();

  @visibleForTesting
  static CheckoutPlanCoordinator? debugCoordinator;

  @visibleForTesting
  static Future<CheckoutRoutingSnapshot> Function()? debugSnapshotResolver;

  static Future<void> _openCheckoutUrl(String? raw) async {
    final uri = validateCheckoutHttpsUri(raw);
    await urlOpener.open(uri);
  }

  static Future<CheckoutRoutingSnapshot> resolveRoutingSnapshot() async {
    if (debugSnapshotResolver != null) {
      return debugSnapshotResolver!();
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception(
          'Faça login para assinar um plano. Se já estiver logado, atualize a página.',
        );
      }
      final email = (user.email ?? '').trim().toLowerCase();
      final svc = PlanosService();
      PlanInfo? plan;
      EffectivePlanAccessDto? dto;
      var planFailed = false;
      var dtoFailed = false;
      try {
        plan = await svc.fetchCurrentPlan(uid: user.uid, email: email);
      } catch (e) {
        planFailed = true;
        debugPrint('[CheckoutPlano] fetchCurrentPlan: $e');
      }
      try {
        dto = await svc.fetchMyEffectivePlanAccess(forceRefresh: true);
      } catch (e) {
        dtoFailed = true;
        debugPrint('[CheckoutPlano] fetchMyEffectivePlanAccess: $e');
      }
      if (planFailed && dtoFailed) {
        return CheckoutRoutingSnapshot.unknown();
      }
      if (plan == null && dto == null && planFailed) {
        return CheckoutRoutingSnapshot.unknown();
      }
      return CheckoutRoutingSnapshot(plan: plan, access: dto);
    } catch (e) {
      debugPrint('[CheckoutPlano] resolveRoutingSnapshot: $e');
      rethrow;
    }
  }

  static CheckoutPlanCoordinator _productionCoordinator() {
    return CheckoutPlanCoordinator(
      resolveSnapshot: resolveRoutingSnapshot,
      callPlanChange: (planApi) =>
          callPlanChangeSubscription(planApi: planApi),
      openNewCheckout: (planApi) => _abrirCheckoutPlanoFluxoNovo(planApi: planApi),
      openRecurringCreate: (planApi) =>
          _abrirCheckoutPlanoRecorrente(planApi: planApi),
      opener: urlOpener,
    );
  }

  /// Abre checkout MP. Assinante recorrente activo + alvo diferente →
  /// [createPlanChangeSubscription]; caso contrário, fluxo one-time/create existente.
  ///
  /// [titulo], [preco] e [quantidade] são ignorados — mantidos na assinatura por compatibilidade
  /// com telas existentes; valores vêm do servidor.
  static Future<CheckoutLaunchResult> abrirCheckoutPlano({
    required String titulo,
    required double preco,
    required String planoId,
    int quantidade = 1,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null && debugCoordinator == null) {
        debugPrint(
          '[PlanosAuthGate] checkout de planos abortado: sem usuário Firebase',
        );
        throw Exception(
          'Faça login para assinar um plano. Se já estiver logado, atualize a página.',
        );
      }

      final canonical = _normalizePlanId(planoId);
      const paid = {
        'mensal',
        'anual',
        'basic_monthly',
        'intermediate_monthly',
        'pro_monthly',
        'pro_yearly',
      };
      final plan = _apiPlanFromCanonical(canonical);
      if (!paid.contains(plan) && !_kPaidCanonicalPlanIds.contains(canonical)) {
        throw Exception('Plano inválido para assinatura paga');
      }

      final coordinator = debugCoordinator ?? _productionCoordinator();
      return await coordinator.run(planoId: canonical);
    } catch (e) {
      debugPrint('❌ Erro ao abrir checkout (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// FLOW A — preferência one-time ou [createPlanSubscription] (RC), sem plan-change.
  static Future<CheckoutLaunchResult> _abrirCheckoutPlanoFluxoNovo({
    required String planApi,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception(
        'Faça login para assinar um plano. Se já estiver logado, atualize a página.',
      );
    }
    final canonical = _normalizePlanId(planApi);
    final plan = _apiPlanFromCanonical(canonical);

    if (RemoteConfigService.shouldUseRecurringPlanBilling(
      uid: user.uid,
      email: user.email,
    )) {
      debugPrint('[PLAN_RECURRING_FLAG] enabled=true (remote config)');
      try {
        return await _abrirCheckoutPlanoRecorrente(planApi: plan);
      } catch (e) {
        if (_shouldFallbackToOneTimeRecurringError(e)) {
          final reason = e.toString().replaceAll('\n', ' ');
          debugPrint(
            '[PLAN_RECURRING_FALLBACK_ONE_TIME] motivo=${reason.length > 180 ? reason.substring(0, 180) : reason}',
          );
        } else {
          rethrow;
        }
      }
    }
    debugPrint('[PLAN_RECURRING_FLAG] enabled=false (fallback one_time)');

    final projectId = Firebase.app().options.projectId;
    final url = Uri.parse(
      'https://southamerica-east1-$projectId.cloudfunctions.net/planCreatePreference',
    );

    String installationId;
    try {
      installationId = await LicenseManager.getDeviceId();
    } catch (_) {
      installationId = '';
    }

    try {
      if (kIsWeb) {
        try {
          await user.reload();
        } catch (e) {
          debugPrint('[PlanosAuthDiag] pre_http reload: $e');
        }
      }
      final tok = await user.getIdToken(true);
      final prov = user.providerData.map((p) => p.providerId).join(',');
      debugPrint(
        '[PlanosAuthDiag] pre_http plan=$plan projectId=$projectId '
        'uidPrefix=${user.uid.length >= 6 ? user.uid.substring(0, 6) : user.uid}… '
        'providers=[$prov] idTokenNonEmpty=${tok != null && tok.isNotEmpty} url=$url',
      );
    } catch (e) {
      debugPrint('[PlanosAuthDiag] pre_http token: $e');
    }

    if (kIsWeb) {
      final viaCall = await _tryPlanCreatePreferenceCallOnWeb(
        plan: plan,
        installationId: installationId,
      );
      final initFromCall = viaCall?['init_point']?.toString() ?? '';
      if (initFromCall.isNotEmpty) {
        debugPrint(
          '[PlanosAuthDiag] checkout planos via planCreatePreferenceCall (OK)',
        );
        await _openCheckoutUrl(initFromCall);
        return CheckoutLaunchResult(
          flowType: CheckoutFlowType.oneTime,
          checkoutUrl: validateCheckoutHttpsUri(initFromCall),
          opened: true,
        );
      }
      debugPrint(
        '[PlanosAuthDiag] fallback planCreatePreference HTTP (callable sem init_point ou falhou)',
      );
    }

    final resp = await _postPlanCreatePreference(
      url: url,
      body: {
        'plan': plan,
        if (installationId.isNotEmpty) 'installationId': installationId,
      },
    );

    if (resp.statusCode == 401) {
      throw Exception(
        'Não foi possível validar a sessão com o servidor. '
        'Atualize a página ou faça login de novo.',
      );
    }
    if (resp.statusCode == 429) {
      throw Exception('Muitas tentativas. Aguarde um minuto e tente de novo.');
    }
    if (resp.statusCode != 200) {
      debugPrint(
        '❌ planCreatePreference ${resp.statusCode} ${resp.body}',
      );
      var msg = 'Não foi possível iniciar o checkout. Tente novamente.';
      try {
        final err = jsonDecode(resp.body);
        if (err is Map) {
          final e = err['error'] ?? err['message'];
          if (e != null && e.toString().trim().isNotEmpty) {
            msg = e.toString();
          }
        }
      } catch (_) {
        final b = resp.body.trim();
        if (b.length > 3 && b.length < 200 && !b.contains('<')) {
          msg = b;
        }
      }
      throw Exception(msg);
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('Resposta inválida do servidor de checkout.');
    }
    final data = Map<String, dynamic>.from(decoded);
    final initPoint = data['init_point']?.toString() ?? '';
    await _openCheckoutUrl(initPoint);
    return CheckoutLaunchResult(
      flowType: CheckoutFlowType.oneTime,
      checkoutUrl: validateCheckoutHttpsUri(initPoint),
      opened: true,
    );
  }

  /// Assinatura recorrente (MP preapproval) — backend [createPlanSubscription].
  static Future<CheckoutLaunchResult> _abrirCheckoutPlanoRecorrente({
    required String planApi,
  }) async {
    Future<HttpsCallableResult<dynamic>> callOnce() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Usuário não autenticado');
      if (kIsWeb) {
        try {
          await user.reload();
        } catch (e) {
          debugPrint('⚠️ [CheckoutPlano] createPlanSubscription reload: $e');
        }
      }
      await user.getIdToken(true);
      final functions =
          FirebaseFunctions.instanceFor(region: 'southamerica-east1');
      final callable = functions.httpsCallable(planSubscriptionCallableName);
      return callable.call(<String, dynamic>{
        'plan': planApi,
      });
    }

    debugPrint(
      '[CheckoutPlano] createPlanSubscription — MP no servidor (Secret Manager)',
    );
    HttpsCallableResult<dynamic> result;
    try {
      result = await callOnce();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        debugPrint(
          '⚠️ [CheckoutPlano] createPlanSubscription unauthenticated — retry após refresh de token',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        result = await callOnce();
      } else {
        rethrow;
      }
    }
    final parsed = parseCreatePlanSubscriptionResponse(result.data);
    await _openCheckoutUrl(parsed.checkoutUrl!.toString());
    return CheckoutLaunchResult(
      flowType: CheckoutFlowType.recurringCreate,
      checkoutUrl: parsed.checkoutUrl,
      opened: true,
    );
  }

  /// Maps [createPlanSubscription] callable payload. Does not navigate.
  @visibleForTesting
  static CheckoutLaunchResult parseCreatePlanSubscriptionResponse(Object? data) {
    if (data is! Map) {
      throw Exception('Resposta inválida do servidor (recorrente).');
    }
    final map = Map<String, dynamic>.from(data);
    final ok = map['ok'] == true;
    final initPoint = map['initPoint']?.toString() ?? '';
    if (!ok || initPoint.isEmpty) {
      throw Exception(
        map['message']?.toString() ?? 'Falha ao iniciar assinatura recorrente.',
      );
    }
    final uri = validateCheckoutHttpsUri(initPoint);
    return CheckoutLaunchResult(
      flowType: CheckoutFlowType.recurringCreate,
      checkoutUrl: uri,
    );
  }

  /// Troca de plano recorrente — backend [createPlanChangeSubscription]. I/O apenas.
  static Future<Map<String, dynamic>> callPlanChangeSubscription({
    required String planApi,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }
    if (kIsWeb) {
      try {
        await user.reload();
      } catch (e) {
        debugPrint('⚠️ [CheckoutPlano] createPlanChangeSubscription reload: $e');
      }
    }
    await user.getIdToken(true);
    final functions =
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable =
        functions.httpsCallable(planChangeSubscriptionCallableName);
    final result = await callable.call(<String, dynamic>{
      'plan': planApi,
    });
    final map = result.data;
    if (map is! Map) {
      throw Exception('Resposta inválida do servidor (troca de plano).');
    }
    return Map<String, dynamic>.from(map);
  }

  static Future<void> abrirCheckoutPix({
    required String titulo,
    required double preco,
    required String pixKey,
  }) async {
    throw UnimplementedError('Checkout PIX em desenvolvimento');
  }

  /// Descontinuado: status de pagamento vem do webhook + doc users no Firestore.
  @Deprecated('Use PlanosService.fetchCurrentPlan / snapshots em users/{uid}')
  static Future<String> verificarStatusPagamento(String preferenceId) async {
    return 'not_found';
  }

  /// Bloqueado: ativação só no backend após confirmação real no Mercado Pago.
  static Future<void> ativarPlanoPagamento({
    required String userEmail,
    required String planoId,
    required String paymentId,
  }) async {
    throw UnsupportedError(
      'A liberação do plano ocorre apenas no servidor após o webhook e consulta '
      'do pagamento no Mercado Pago. O app não pode ativar plano localmente.',
    );
  }
}
