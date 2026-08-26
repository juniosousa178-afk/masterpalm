import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/core/master_plan_admin_messages.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/checkout_service.dart';
import 'package:master_palm/services/checkout_url_opener.dart';
import 'package:master_palm/services/planos_service.dart';

/// URI reservada — nunca mercadopago.com / init_point real.
const kFakeCheckoutUrl = 'https://checkout.test.invalid/fake-init';

class RecordingCheckoutUrlOpener implements CheckoutUrlOpener {
  final List<Uri> opened = [];
  bool fail = false;

  @override
  Future<void> open(Uri url) async {
    if (fail) throw Exception('Não foi possível abrir o Mercado Pago.');
    opened.add(url);
  }
}

PlanInfo _basicRecurring({
  String? pendingTo,
  String pendingStatus = 'pending',
}) {
  return PlanInfo(
    planId: PlanId.basicMonthly,
    status: 'active',
    trialing: false,
    currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
    trialUsed: true,
    manualOverride: false,
    billingVersion: 2,
    billingSource: 'mp_subscription',
    providerSubscriptionId: 'preap_test_fake',
    billingMode: 'recurring',
    pendingPlanChangeToPlanId: pendingTo,
    pendingPlanChangeStatus: pendingTo == null ? null : pendingStatus,
  );
}

EffectivePlanAccessDto _dtoBasicRecurring() {
  return EffectivePlanAccessDto(
    contractedPlanId: PlanId.basicMonthly,
    effectivePlanId: PlanId.basicMonthly,
    accessSource: 'paid_subscription',
    effectiveStatus: 'active',
    courtesy: const MasterPlanCourtesySummary(active: false),
    renewal: const MasterPlanRenewalSummary(
      active: true,
      cancelAtPeriodEnd: false,
    ),
    subscription: const PlanAccessSubscriptionSummary(
      provider: 'mercado_pago',
      maskedProviderSubscriptionId: 'pre***fake',
    ),
  );
}

/// Espelha `_activePlanIdForDisplay` em planos_screen.dart (linhas 679–685).
String? activePlanIdForDisplay({
  PlanInfo? plan,
  EffectivePlanAccessDto? access,
}) {
  final fromPlan = plan?.planId.trim();
  if (fromPlan != null && fromPlan.isNotEmpty) return fromPlan;
  final fromDto = access?.contractedPlanId?.trim();
  if (fromDto != null && fromDto.isNotEmpty) return fromDto;
  return null;
}

/// Espelha o ramo de `statusLabel` em `_header` (linhas 688–698).
String headerStatusLabel({
  PlanInfo? plan,
  EffectivePlanAccessDto? access,
}) {
  final displayPlanId = activePlanIdForDisplay(plan: plan, access: access);
  var statusLabel = 'Sem plano';
  if (displayPlanId != null) {
    statusLabel = masterPlanIdLabel(displayPlanId);
    final status = plan?.status;
    if (status == 'active' || status == 'trialing' || plan == null) {
      statusLabel = '$statusLabel (ativo)';
    }
  }
  return statusLabel;
}

CheckoutPlanCoordinator _coord({
  required CheckoutRoutingSnapshot snapshot,
  required RecordingCheckoutUrlOpener opener,
  Map<String, dynamic> Function(String planApi)? planChange,
  CheckoutLaunchResult Function(String planApi)? newCheckout,
  Future<Map<String, dynamic>> Function(String planApi)? planChangeAsync,
}) {
  return CheckoutPlanCoordinator(
    resolveSnapshot: () async => snapshot,
    callPlanChange: (planApi) async {
      if (planChangeAsync != null) return planChangeAsync(planApi);
      if (planChange != null) return planChange(planApi);
      return {
        'ok': true,
        'initPoint': kFakeCheckoutUrl,
        'changeId': 'chg_test_fake',
        'fromPlanId': 'basic_monthly',
        'requestedPlanId': planApi,
      };
    },
    openNewCheckout: (planApi) async {
      if (newCheckout != null) return newCheckout(planApi);
      return const CheckoutLaunchResult(
        flowType: CheckoutFlowType.oneTime,
        opened: true,
      );
    },
    opener: opener,
  );
}

void main() {
  test('FAKE_ENVIRONMENT: URI sintética sem domínio MP', () {
    final uri = validateCheckoutHttpsUri(kFakeCheckoutUrl);
    expect(uri.host, 'checkout.test.invalid');
    expect(uri.host.contains('mercadopago'), isFalse);
    expect(kFakeCheckoutUrl.contains('mercadopago'), isFalse);
    expect(kFakeCheckoutUrl.contains('init_point'), isFalse);
  });

  test('A. basic_monthly recorrente → pro_monthly', () async {
    final opener = RecordingCheckoutUrlOpener();
    var newCount = 0;
    final plan = _basicRecurring();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: plan,
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
      newCheckout: (_) {
        newCount++;
        return const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime);
      },
    );

    final result = await coord.run(planoId: 'pro_monthly');

    expect(plan.planId, PlanId.basicMonthly, reason: 'A_CURRENT_PLAN_RENDERED');
    expect(coord.planChangeCallCount, 1);
    expect(coord.newCheckoutCallCount, 0);
    expect(newCount, 0);
    expect(opener.opened, hasLength(1));
    expect(opener.opened.single.toString(), kFakeCheckoutUrl);
    expect(result.flowType, CheckoutFlowType.planChange);
    expect(plan.planId, isNot(PlanId.proMonthly));
  });

  test('B. _plan null + contractedPlanId basic → plan-change', () async {
    final opener = RecordingCheckoutUrlOpener();
    var newCount = 0;
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: null,
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
      newCheckout: (_) {
        newCount++;
        return const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime);
      },
    );

    final result = await coord.run(planoId: 'pro_monthly');
    expect(coord.planChangeCallCount, 1);
    expect(newCount, 0);
    expect(result.flowType, CheckoutFlowType.planChange);
    expect(
      headerStatusLabel(plan: null, access: _dtoBasicRecurring()),
      'Básico (ativo)',
    );
    expect(
      headerStatusLabel(plan: null, access: _dtoBasicRecurring())
          .contains('Sem plano'),
      isFalse,
    );
  });

  test('C. pending Pro: UI actual vs pendente, sem duplicar', () async {
    final opener = RecordingCheckoutUrlOpener();
    final plan = _basicRecurring(pendingTo: PlanId.proMonthly);
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: plan,
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
    );

    expect(plan.planId, PlanId.basicMonthly);
    expect(plan.hasPendingChangeTo(PlanId.proMonthly), isTrue);
    expect(masterPlanIdLabel(plan.planId), 'Básico');
    expect(masterPlanIdLabel(plan.pendingPlanChangeToPlanId), 'Pro mensal');
    expect(PlanMatrix.tierForPlanId(plan.planId), PlanAccessTier.basic);
    expect(PlanMatrix.tierForPlanId(plan.planId), isNot(PlanAccessTier.pro));

    await expectLater(
      coord.run(planoId: 'pro_monthly'),
      throwsA(
        predicate<Object>(
          (e) => e.toString().contains('Já existe uma alteração'),
        ),
      ),
    );
    expect(coord.planChangeCallCount, 0);
    expect(coord.newCheckoutCallCount, 0);
    expect(opener.opened, isEmpty);
    expect(plan.planId, PlanId.basicMonthly);
  });

  test('D. mesmo plano: zero checkout / redirect', () async {
    final opener = RecordingCheckoutUrlOpener();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
    );

    final result = await coord.run(planoId: 'basic_monthly');
    expect(result.flowType, CheckoutFlowType.alreadyActive);
    expect(coord.planChangeCallCount, 0);
    expect(coord.newCheckoutCallCount, 0);
    expect(opener.opened, isEmpty);
  });

  test('E. estado desconhecido: erro visível, zero I/O', () async {
    final opener = RecordingCheckoutUrlOpener();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot.unknown(),
      opener: opener,
    );

    await expectLater(
      coord.run(planoId: 'pro_monthly'),
      throwsA(
        predicate<Object>(
          (e) => e
              .toString()
              .contains('Não foi possível confirmar o seu plano atual'),
        ),
      ),
    );
    expect(coord.planChangeCallCount, 0);
    expect(coord.newCheckoutCallCount, 0);
    expect(opener.opened, isEmpty);
  });

  test('F. initPoint inválido: zero redirect', () async {
    Future<void> caseOf(String? raw) async {
      final opener = RecordingCheckoutUrlOpener();
      final coord = _coord(
        snapshot: CheckoutRoutingSnapshot(
          plan: _basicRecurring(),
          access: _dtoBasicRecurring(),
        ),
        opener: opener,
        planChange: (_) => {'ok': true, 'initPoint': raw},
      );
      await expectLater(
        coord.run(planoId: 'pro_monthly'),
        throwsA(isA<CheckoutUrlValidationException>()),
      );
      expect(opener.opened, isEmpty);
    }

    await caseOf(null);
    await caseOf('');
    await caseOf('http://checkout.test.invalid/fake');
    await caseOf('javascript:alert(1)');
    await caseOf('not a url');
  });

  test('G. Web same-tab assign, zero popup/nativo', () async {
    var assign = 0;
    var native = 0;
    var popup = 0;
    final opener = PlatformCheckoutUrlOpener(
      isWeb: true,
      webAssign: (_) => assign++,
      nativeLaunch: (_) async {
        native++;
        return true;
      },
    );
    final coord = CheckoutPlanCoordinator(
      resolveSnapshot: () async => CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      callPlanChange: (_) async => {
        'ok': true,
        'initPoint': kFakeCheckoutUrl,
      },
      openNewCheckout: (_) async =>
          const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime),
      opener: opener,
    );

    await coord.run(planoId: 'pro_monthly');
    expect(assign, 1);
    expect(native, 0);
    expect(popup, 0);
    expect(coord.planChangeCallCount, 1);
  });

  test('H. nativo launch, zero web assign', () async {
    var assign = 0;
    var native = 0;
    final opener = PlatformCheckoutUrlOpener(
      isWeb: false,
      webAssign: (_) => assign++,
      nativeLaunch: (_) async {
        native++;
        return true;
      },
    );
    final coord = CheckoutPlanCoordinator(
      resolveSnapshot: () async => CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      callPlanChange: (_) async => {
        'ok': true,
        'initPoint': kFakeCheckoutUrl,
      },
      openNewCheckout: (_) async =>
          const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime),
      opener: opener,
    );

    await coord.run(planoId: 'pro_monthly');
    expect(native, 1);
    expect(assign, 0);
  });

  test('I. sem recorrente: FLOW A, plan-change 0', () async {
    final opener = RecordingCheckoutUrlOpener();
    final coord = _coord(
      snapshot: const CheckoutRoutingSnapshot(
        plan: PlanInfo(
          planId: PlanId.freeLimited,
          status: 'active',
          trialing: false,
          currentPeriodEnd: null,
          trialUsed: true,
          manualOverride: false,
        ),
      ),
      opener: opener,
    );

    final result = await coord.run(planoId: 'pro_monthly');
    expect(coord.newCheckoutCallCount, 1);
    expect(coord.planChangeCallCount, 0);
    expect(opener.opened, isEmpty);
    expect(result.flowType, CheckoutFlowType.oneTime);
  });

  test('J. pending payment: effective continua basic', () {
    final pending = _basicRecurring(pendingTo: PlanId.proMonthly);
    expect(pending.planId, PlanId.basicMonthly);
    expect(PlanMatrix.tierForPlanId(pending.planId), PlanAccessTier.basic);
    expect(PlanMatrix.tierForPlanId(pending.planId), isNot(PlanAccessTier.pro));
    expect(
      PlanMatrix.tierForPlanId(pending.pendingPlanChangeToPlanId),
      PlanAccessTier.pro,
    );
    expect(pending.hasPendingChangeTo(PlanId.proMonthly), isTrue);
  });

  test('19. duplo clique: lock in-flight (espelha isLoading da UI)', () async {
    final opener = RecordingCheckoutUrlOpener();
    final started = Completer<void>();
    final release = Completer<Map<String, dynamic>>();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
      planChangeAsync: (_) async {
        if (!started.isCompleted) started.complete();
        return release.future;
      },
    );

    var inFlight = false;
    Future<void> click() async {
      if (inFlight) return;
      inFlight = true;
      try {
        await coord.run(planoId: 'pro_monthly');
      } finally {
        inFlight = false;
      }
    }

    final first = click();
    await started.future;
    await click();
    expect(coord.planChangeCallCount, 1);

    release.complete({
      'ok': true,
      'initPoint': kFakeCheckoutUrl,
      'changeId': 'chg_test_fake',
    });
    await first;
    expect(coord.planChangeCallCount, 1);
    expect(opener.opened, hasLength(1));
  });

  test('19b. loading recupera após falha fake', () async {
    final opener = RecordingCheckoutUrlOpener();
    var loading = false;
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
      planChange: (_) => throw Exception('internal timeout'),
    );

    loading = true;
    try {
      await coord.run(planoId: 'pro_monthly');
      fail('expected throw');
    } catch (_) {
      // visível no caller da UI via SnackBar
    } finally {
      loading = false;
    }
    expect(loading, isFalse);
    expect(coord.newCheckoutCallCount, 0);
    expect(opener.opened, isEmpty);
  });

  test('20/21. erro plan-change não cai em create novo', () async {
    final opener = RecordingCheckoutUrlOpener();
    var newCount = 0;
    final coord = CheckoutPlanCoordinator(
      resolveSnapshot: () async => CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      callPlanChange: (_) async => throw Exception('internal timeout'),
      openNewCheckout: (_) async {
        newCount++;
        return const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime);
      },
      opener: opener,
    );

    await expectLater(coord.run(planoId: 'pro_monthly'), throwsException);
    expect(newCount, 0);
    expect(opener.opened, isEmpty);
  });

  test('20. opener falha: erro visível, sem redirect silencioso', () async {
    final opener = RecordingCheckoutUrlOpener()..fail = true;
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
    );

    await expectLater(
      coord.run(planoId: 'pro_monthly'),
      throwsA(
        predicate<Object>(
          (e) => e.toString().contains('Não foi possível abrir o Mercado Pago'),
        ),
      ),
    );
    expect(opener.opened, isEmpty);
  });

  test('18. header pago conhecido não resolve para Sem plano', () {
    expect(
      headerStatusLabel(plan: null, access: _dtoBasicRecurring()),
      'Básico (ativo)',
    );
    expect(
      headerStatusLabel(plan: _basicRecurring(), access: _dtoBasicRecurring()),
      'Básico (ativo)',
    );
    expect(
      headerStatusLabel(plan: null, access: null),
      'Sem plano',
    );
  });
}
