import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/checkout_service.dart';
import 'package:master_palm/services/checkout_url_opener.dart';
import 'package:master_palm/services/planos_service.dart';

class RecordingCheckoutUrlOpener implements CheckoutUrlOpener {
  final List<Uri> opened = [];

  @override
  Future<void> open(Uri url) async {
    opened.add(url);
  }
}

PlanInfo _freeLimited({String? providerSubscriptionId}) {
  return PlanInfo(
    planId: PlanId.freeLimited,
    status: 'active',
    trialing: false,
    currentPeriodEnd: null,
    trialUsed: true,
    manualOverride: false,
    providerSubscriptionId: providerSubscriptionId,
  );
}

PlanInfo _trial(String planId) {
  return PlanInfo(
    planId: planId,
    status: 'trialing',
    trialing: true,
    currentPeriodEnd: DateTime.now().add(const Duration(days: 10)),
    trialUsed: false,
    manualOverride: false,
  );
}

PlanInfo _oneTimePro() {
  return PlanInfo(
    planId: PlanId.proMonthly,
    status: 'active',
    trialing: false,
    currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
    trialUsed: true,
    manualOverride: false,
  );
}

PlanInfo _basicPaid() {
  return PlanInfo(
    planId: PlanId.basicMonthly,
    status: 'active',
    trialing: false,
    currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
    trialUsed: true,
    manualOverride: false,
  );
}

PlanInfo _basicRecurring() {
  return PlanInfo(
    planId: PlanId.basicMonthly,
    status: 'active',
    trialing: false,
    currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
    trialUsed: true,
    manualOverride: false,
    billingVersion: 2,
    billingSource: 'mp_subscription',
    providerSubscriptionId: 'preap_paid',
    billingMode: 'recurring',
  );
}

CheckoutPlanCoordinator _p1eCoord({
  required CheckoutRoutingSnapshot snapshot,
  required RecordingCheckoutUrlOpener opener,
  required int Function() bumpRecurring,
  required int Function() bumpPreference,
  required int Function() bumpChange,
  Object? recurringError,
  CheckoutLaunchResult? recurringResult,
}) {
  const init =
      'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=pre_p1e';
  return CheckoutPlanCoordinator(
    resolveSnapshot: () async => snapshot,
    callPlanChange: (planApi) async {
      bumpChange();
      return {
        'ok': true,
        'initPoint':
            'https://www.mercadopago.com.br/checkout/v1/redirect?pref_id=chg',
        'changeId': 'chg_p1e',
        'requestedPlanId': planApi,
      };
    },
    openNewCheckout: (planApi) async {
      bumpPreference();
      return const CheckoutLaunchResult(
        flowType: CheckoutFlowType.oneTime,
        opened: true,
      );
    },
    openRecurringCreate: (planApi) async {
      bumpRecurring();
      if (recurringError != null) throw recurringError;
      if (recurringResult != null) return recurringResult;
      final uri = validateCheckoutHttpsUri(init);
      await opener.open(uri);
      return CheckoutLaunchResult(
        flowType: CheckoutFlowType.recurringCreate,
        checkoutUrl: uri,
        opened: true,
      );
    },
    opener: opener,
  );
}

void main() {
  const recurringInit =
      'https://www.mercadopago.com.br/subscriptions/checkout?preapproval_id=pre_p1e';

  test('T1 free_limited → pro_monthly uses createPlanSubscription only', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot(plan: _freeLimited()),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );

    final result = await coord.run(planoId: 'pro_monthly');

    expect(recurring, 1);
    expect(preference, 0);
    expect(change, 0);
    expect(coord.recurringCreateCallCount, 1);
    expect(coord.newCheckoutCallCount, 0);
    expect(coord.planChangeCallCount, 0);
    expect(result.flowType, CheckoutFlowType.recurringCreate);
    expect(opener.opened, [Uri.parse(recurringInit)]);
  });

  test('T2 eligible trials → pro_monthly use createPlanSubscription', () async {
    for (final id in [PlanId.freeTrial30d, PlanId.freeTrial90d]) {
      final opener = RecordingCheckoutUrlOpener();
      var recurring = 0;
      var preference = 0;
      var change = 0;
      final coord = _p1eCoord(
        snapshot: CheckoutRoutingSnapshot(plan: _trial(id)),
        opener: opener,
        bumpRecurring: () => ++recurring,
        bumpPreference: () => ++preference,
        bumpChange: () => ++change,
      );
      final result = await coord.run(planoId: 'mensal');
      expect(recurring, 1, reason: id);
      expect(preference, 0, reason: id);
      expect(change, 0, reason: id);
      expect(result.flowType, CheckoutFlowType.recurringCreate);
    }
  });

  test('T2b empty/unset plan → pro uses createPlanSubscription', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: const CheckoutRoutingSnapshot(),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );
    await coord.run(planoId: 'pro_monthly');
    expect(recurring, 1);
    expect(preference, 0);
    expect(change, 0);
  });

  test('T3 Basic/paid is not Free create', () async {
    expect(isP1eFreeEligible(CheckoutRoutingSnapshot(plan: _basicPaid())), isFalse);
    expect(
      isP1eFreeEligible(CheckoutRoutingSnapshot(plan: _basicRecurring())),
      isFalse,
    );
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot(plan: _basicPaid()),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );
    await coord.run(planoId: 'pro_monthly');
    expect(recurring, 0);
    expect(preference, 1);
    expect(change, 0);
  });

  test('T3 paid recurring → other paid uses plan change only', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot(plan: _basicRecurring()),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );
    final result = await coord.run(planoId: 'pro_monthly');
    expect(change, 1);
    expect(recurring, 0);
    expect(preference, 0);
    expect(result.flowType, CheckoutFlowType.planChange);
  });

  test('T4 Pro → Pro no checkout callables', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot(plan: _oneTimePro()),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );
    final result = await coord.run(planoId: 'pro_monthly');
    expect(result.flowType, CheckoutFlowType.alreadyActive);
    expect(recurring, 0);
    expect(preference, 0);
    expect(change, 0);
    expect(opener.opened, isEmpty);
  });

  test('T7 unknown/ambiguous snapshot fails closed', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot.unknown(),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );
    await expectLater(coord.run(planoId: 'pro_monthly'), throwsException);
    expect(recurring, 0);
    expect(preference, 0);
    expect(change, 0);
    expect(opener.opened, isEmpty);
    expect(isP1eFreeEligible(CheckoutRoutingSnapshot.unknown()), isFalse);
  });

  test('T6 stale Free + providerSubscriptionId is not P1E Free', () {
    expect(
      isP1eFreeEligible(
        CheckoutRoutingSnapshot(
          plan: _freeLimited(providerSubscriptionId: 'pre_live'),
        ),
      ),
      isFalse,
    );
  });

  test('T9 recurring callable failure does not fall back to one-time', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot(plan: _freeLimited()),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
      recurringError: Exception('PLAN_BILLING_OPERATION_IN_PROGRESS'),
    );
    await expectLater(coord.run(planoId: 'pro_monthly'), throwsException);
    expect(recurring, 1);
    expect(preference, 0);
    expect(change, 0);
    expect(opener.opened, isEmpty);
  });

  test('T10 missing/invalid initPoint: no navigation', () {
    expect(
      () => CheckoutService.parseCreatePlanSubscriptionResponse({'ok': true}),
      throwsException,
    );
    expect(
      () => CheckoutService.parseCreatePlanSubscriptionResponse({
        'ok': true,
        'initPoint': 'http://insecure.example/x',
      }),
      throwsA(isA<CheckoutUrlValidationException>()),
    );
    expect(
      () => CheckoutService.parseCreatePlanSubscriptionResponse({
        'ok': false,
        'initPoint': recurringInit,
      }),
      throwsException,
    );
  });

  test('T8/T31 valid initPoint is https and opener is same-tab contract', () {
    final parsed = CheckoutService.parseCreatePlanSubscriptionResponse({
      'ok': true,
      'initPoint': recurringInit,
    });
    expect(parsed.checkoutUrl!.scheme, 'https');
    expect(parsed.flowType, CheckoutFlowType.recurringCreate);
    expect(parsed.opened, isFalse);
  });

  test('existing one-time Pro is not migrated / not P1E Free', () {
    expect(isP1eFreeEligible(CheckoutRoutingSnapshot(plan: _oneTimePro())), isFalse);
  });

  test('Free → Basic stays one-time (target is not Pro)', () async {
    final opener = RecordingCheckoutUrlOpener();
    var recurring = 0;
    var preference = 0;
    var change = 0;
    final coord = _p1eCoord(
      snapshot: CheckoutRoutingSnapshot(plan: _freeLimited()),
      opener: opener,
      bumpRecurring: () => ++recurring,
      bumpPreference: () => ++preference,
      bumpChange: () => ++change,
    );
    await coord.run(planoId: 'basic_monthly');
    expect(recurring, 0);
    expect(preference, 1);
    expect(isP1eProTarget('basic_monthly'), isFalse);
    expect(isP1eProTarget('pro_yearly'), isTrue);
  });
}
