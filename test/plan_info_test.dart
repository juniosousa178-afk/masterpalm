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
