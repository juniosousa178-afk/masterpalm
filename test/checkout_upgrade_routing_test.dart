import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/services/checkout_service.dart';
import 'package:master_palm/services/checkout_url_opener.dart';
import 'package:master_palm/services/planos_service.dart';

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

EffectivePlanAccessDto _dtoBasicRecurring({String? contracted}) {
  return EffectivePlanAccessDto(
    contractedPlanId: contracted ?? PlanId.basicMonthly,
    effectivePlanId: contracted ?? PlanId.basicMonthly,
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

CheckoutPlanCoordinator _coord({
  required CheckoutRoutingSnapshot snapshot,
  required RecordingCheckoutUrlOpener opener,
  Map<String, dynamic> Function(String planApi)? planChange,
  CheckoutLaunchResult Function(String planApi)? newCheckout,
}) {
  return CheckoutPlanCoordinator(
    resolveSnapshot: () async => snapshot,
    callPlanChange: (planApi) async {
      if (planChange != null) return planChange(planApi);
      return {
        'ok': true,
        'initPoint': 'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=fake-test',
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
  const fakeInit =
      'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=fake-test';

  test('1. basic_monthly recorrente → pro_monthly chama plan-change uma vez',
      () async {
    final opener = RecordingCheckoutUrlOpener();
    var changePlans = <String>[];
    var newCount = 0;
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
      planChange: (p) {
        changePlans.add(p);
        return {
          'ok': true,
          'initPoint': fakeInit,
          'changeId': 'chg_test_fake',
        };
      },
      newCheckout: (p) {
        newCount++;
        return const CheckoutLaunchResult(
          flowType: CheckoutFlowType.oneTime,
          opened: true,
        );
      },
    );

    final result = await coord.run(planoId: 'pro_monthly');

    expect(coord.planChangeCallCount, 1);
    expect(changePlans, ['pro_monthly']);
    expect(coord.newCheckoutCallCount, 0);
    expect(newCount, 0);
    expect(opener.opened, hasLength(1));
    expect(opener.opened.single.scheme, 'https');
    expect(result.flowType, CheckoutFlowType.planChange);
    expect(result.opened, isTrue);
    expect(result.pendingChangeId, 'chg_test_fake');
  });

  test('2. sem recorrente activo preserva FLOW A', () async {
    final opener = RecordingCheckoutUrlOpener();
    var newPlans = <String>[];
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
      newCheckout: (p) {
        newPlans.add(p);
        return const CheckoutLaunchResult(
          flowType: CheckoutFlowType.oneTime,
          opened: true,
        );
      },
    );

    final result = await coord.run(planoId: 'pro_monthly');

    expect(coord.planChangeCallCount, 0);
    expect(coord.newCheckoutCallCount, 1);
    expect(newPlans, ['pro_monthly']);
    expect(opener.opened, isEmpty);
    expect(result.flowType, CheckoutFlowType.oneTime);
  });

  test('3. plan-change + Web same-tab assign uma vez', () async {
    var assign = 0;
    var native = 0;
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
      callPlanChange: (_) async => {'ok': true, 'initPoint': fakeInit},
      openNewCheckout: (_) async =>
          const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime),
      opener: opener,
    );

    await coord.run(planoId: 'mensal');

    expect(assign, 1);
    expect(native, 0);
    expect(coord.planChangeCallCount, 1);
    expect(coord.newCheckoutCallCount, 0);
  });

  test('4. plan-change + nativo launch uma vez', () async {
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
      callPlanChange: (_) async => {'ok': true, 'initPoint': fakeInit},
      openNewCheckout: (_) async =>
          const CheckoutLaunchResult(flowType: CheckoutFlowType.oneTime),
      opener: opener,
    );

    await coord.run(planoId: 'pro_monthly');

    expect(native, 1);
    expect(assign, 0);
  });

  test('5. initPoint null/vazio não redireciona', () async {
    final opener = RecordingCheckoutUrlOpener();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
      planChange: (_) => {'ok': true, 'initPoint': ''},
    );

    await expectLater(
      coord.run(planoId: 'pro_monthly'),
      throwsA(isA<CheckoutUrlValidationException>()),
    );
    expect(opener.opened, isEmpty);
  });

  test('6. opener Web falha → erro visível', () async {
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

  test('7. _plan null + contractedPlanId basic recorrente → FLOW B', () async {
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
    expect(coord.newCheckoutCallCount, 0);
    expect(newCount, 0);
    expect(result.flowType, CheckoutFlowType.planChange);
    expect(opener.opened, hasLength(1));
  });

  test('8. pending pro_monthly não cria segundo change', () async {
    final opener = RecordingCheckoutUrlOpener();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: _basicRecurring(pendingTo: PlanId.proMonthly),
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
    );

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
  });

  test('9. clique não muta currentPlanId — permanece basic', () async {
    final plan = _basicRecurring();
    final opener = RecordingCheckoutUrlOpener();
    final coord = _coord(
      snapshot: CheckoutRoutingSnapshot(
        plan: plan,
        access: _dtoBasicRecurring(),
      ),
      opener: opener,
    );

    await coord.run(planoId: 'pro_monthly');

    expect(plan.planId, PlanId.basicMonthly);
    expect(plan.planId, isNot(PlanId.proMonthly));
  });

  test('10. pagamento pendente/failed preserva basic como efectivo', () {
    final pending = _basicRecurring(pendingTo: PlanId.proMonthly);
    expect(pending.planId, PlanId.basicMonthly);
    expect(pending.hasPendingChangeTo(PlanId.proMonthly), isTrue);
    expect(pending.planId, isNot(PlanId.proMonthly));

    final abandoned = _basicRecurring();
    expect(abandoned.planId, PlanId.basicMonthly);
    expect(abandoned.hasPendingPlanChange, isFalse);
    expect(abandoned.isPaidSubscription, isTrue);
  });

  test('estado desconhecido falha visível sem checkout', () async {
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

  test('mesmo plano recorrente não duplica checkout', () async {
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

  test('URL inválida (não https) falha fechado', () {
    expect(
      () => validateCheckoutHttpsUri('javascript:alert(1)'),
      throwsA(isA<CheckoutUrlValidationException>()),
    );
    expect(
      () => validateCheckoutHttpsUri('http://example.com/checkout'),
      throwsA(isA<CheckoutUrlValidationException>()),
    );
    expect(
      () => validateCheckoutHttpsUri(''),
      throwsA(isA<CheckoutUrlValidationException>()),
    );
    expect(
      () => validateCheckoutHttpsUri(null),
      throwsA(isA<CheckoutUrlValidationException>()),
    );
  });

  test('DTO fromMap parseia subscription mascarada', () {
    final dto = EffectivePlanAccessDto.fromMap({
      'contractedPlanId': 'basic_monthly',
      'effectivePlanId': 'basic_monthly',
      'accessSource': 'paid_subscription',
      'effectiveStatus': 'active',
      'subscription': {
        'provider': 'mercado_pago',
        'maskedProviderSubscriptionId': 'pre***fake',
      },
    });
    expect(dto.subscription.hasMaskedSubscriptionId, isTrue);
    expect(dto.contractedPlanId, 'basic_monthly');
  });

  test('CASE 7 failed-precondition Use assinatura comum → FLOW A', () async {
    final opener = RecordingCheckoutUrlOpener();
    var newCount = 0;
    final coord = CheckoutPlanCoordinator(
      resolveSnapshot: () async => CheckoutRoutingSnapshot(
        plan: _basicRecurring(),
        access: _dtoBasicRecurring(),
      ),
      callPlanChange: (_) async {
        throw Exception(
          'failed-precondition: Não há assinatura recorrente ativa para trocar. Use assinatura comum.',
        );
      },
      openNewCheckout: (_) async {
        newCount++;
        return const CheckoutLaunchResult(
          flowType: CheckoutFlowType.oneTime,
          opened: true,
        );
      },
      opener: opener,
    );

    final result = await coord.run(planoId: 'pro_monthly');
    expect(coord.planChangeCallCount, 1);
    expect(newCount, 1);
    expect(result.flowType, CheckoutFlowType.oneTime);
  });

  test('CASE 8 erro interno não cai em create novo', () async {
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
}
