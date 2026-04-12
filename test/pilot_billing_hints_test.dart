import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  group('PilotBillingOperationHints', () {
    test('doc v2 + RC efetivo por allowlist', () {
      const snap = PlanCanonicalBillingSnapshot(
        currentPlanId: 'pro_monthly',
        status: 'active',
        currentPeriodEnd: null,
        cancelAtPeriodEnd: false,
        billingVersion: 2,
        billingSource: 'mp_preapproval_pending',
        providerSubscriptionId: 'preap_123',
        usesMercadoRecurringPlanBilling: true,
        manualOverride: false,
      );
      final h = PilotBillingOperationHints.fromInputs(
        snapshot: snap,
        rcGlobal: false,
        rcEffective: true,
      );
      expect(h.syncCallableLikelyUseful, true);
      expect(h.docCancelRenewLabel.contains('v2'), true);
      expect(h.checkoutRolloutLabel.contains('allowlist'), true);
      expect(h.asPilotSummaryLines.contains('presente'), true);
    });

    test('sem providerSubscriptionId — sync não útil', () {
      const snap = PlanCanonicalBillingSnapshot(
        currentPlanId: 'pro_monthly',
        status: 'active',
        currentPeriodEnd: null,
        cancelAtPeriodEnd: false,
        billingVersion: null,
        billingSource: null,
        providerSubscriptionId: null,
        usesMercadoRecurringPlanBilling: false,
        manualOverride: false,
      );
      final h = PilotBillingOperationHints.fromInputs(
        snapshot: snap,
        rcGlobal: true,
        rcEffective: true,
      );
      expect(h.syncCallableLikelyUseful, false);
      expect(h.providerSubscriptionLine.contains('ausente'), true);
    });

    test('RC efetivo off — checkout só legado', () {
      final h = PilotBillingOperationHints.fromInputs(
        snapshot: null,
        rcGlobal: false,
        rcEffective: false,
      );
      expect(h.checkoutRolloutLabel.contains('só legado'), true);
    });
  });
}
