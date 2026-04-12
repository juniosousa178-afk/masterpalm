import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  test('SupportPlanBillingSnapshotResult.fromMap e asSupportText', () {
    final r = SupportPlanBillingSnapshotResult.fromMap({
      'ok': true,
      'found': true,
      'reason': null,
      'snapshot': {
        'uid': 'u1',
        'email': 'a@b.com',
        'usersDocExists': true,
        'currentPlanId': 'pro_monthly',
        'status': 'active',
        'trialing': false,
        'currentPeriodEnd': '2026-12-01T00:00:00.000Z',
        'cancelAtPeriodEnd': false,
        'billingVersion': 2,
        'billingSource': 'mp_subscription',
        'providerSubscriptionId': 'x',
        'manualOverride': null,
        'manualGrant': {'present': false},
        'usesMercadoRecurringPlanBilling': true,
        'interpretationLabels': 'doc_v2_mp',
      },
    });
    expect(r.ok, true);
    expect(r.found, true);
    expect(r.asSupportText.contains('doc_v2_mp'), true);
    expect(r.asSupportText.contains('u1'), true);
  });
}
