import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  group('PlanInfo — cancelamento fim de período', () {
    test('cancelAtPeriodEnd default false', () {
      const p = PlanInfo(
        planId: PlanId.proMonthly,
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: true,
        manualOverride: false,
      );
      expect(p.cancelAtPeriodEnd, false);
    });

    test('billing v2: usesMercadoRecurringPlanBilling quando billingVersion == 2', () {
      const p = PlanInfo(
        planId: PlanId.proMonthly,
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: true,
        manualOverride: false,
        billingVersion: 2,
        billingSource: 'mp_preapproval_pending',
        providerSubscriptionId: 'preap_1',
      );
      expect(p.usesMercadoRecurringPlanBilling, true);
      final snap = PlanCanonicalBillingSnapshot.fromPlanInfo(p);
      expect(snap.usesMercadoRecurringPlanBilling, true);
      expect(snap.asSupportText.contains('billingVersion=2'), true);
    });

    test('legado: sem billing v2 não usa MP recorrente na decisão', () {
      const p = PlanInfo(
        planId: PlanId.proMonthly,
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: true,
        manualOverride: false,
      );
      expect(p.usesMercadoRecurringPlanBilling, false);
    });

    test('defensivo: mp_ + providerSubscriptionId sem billingVersion', () {
      const p = PlanInfo(
        planId: PlanId.proMonthly,
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: true,
        manualOverride: false,
        billingSource: 'mp_subscription',
        providerSubscriptionId: 'x',
      );
      expect(p.usesMercadoRecurringPlanBilling, true);
    });

    test('isPaidSubscription reconhece planos pagos', () {
      const p = PlanInfo(
        planId: PlanId.basicMonthly,
        status: 'active',
        trialing: false,
        currentPeriodEnd: null,
        trialUsed: true,
        manualOverride: false,
      );
      expect(p.isPaidSubscription, true);
      expect(
        const PlanInfo(
          planId: PlanId.freeLimited,
          status: 'active',
          trialing: false,
          currentPeriodEnd: null,
          trialUsed: true,
          manualOverride: false,
        ).isPaidSubscription,
        false,
      );
    });
  });
}
