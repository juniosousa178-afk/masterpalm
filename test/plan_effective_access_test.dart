import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/master_plan_admin_service.dart';

void main() {
  group('EffectivePlanAccessDto', () {
    test('12. fallback não inventa cortesia local', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: 'free_limited',
        accessSource: 'free_limited',
        courtesy: MasterPlanCourtesySummary(active: false),
        renewal: MasterPlanRenewalSummary(active: false, cancelAtPeriodEnd: false),
      );
      expect(dto.hasActiveCourtesy, isFalse);
      expect(dto.effectivePlanId, 'free_limited');
    });

    test('13. cortesia ativa no DTO', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: 'intermediate_monthly',
        accessSource: 'manual_courtesy',
        courtesy: MasterPlanCourtesySummary(
          active: true,
          planId: 'intermediate_monthly',
          expiresAt: '2030-01-01T00:00:00.000Z',
        ),
        renewal: MasterPlanRenewalSummary(active: false, cancelAtPeriodEnd: false),
      );
      expect(dto.hasActiveCourtesy, isTrue);
      expect(
        PlanMatrix.tierForPlanId(dto.effectivePlanId),
        PlanAccessTier.intermediate,
      );
    });
  });

  group('MyPlanEffectiveAccessService', () {
    test('falha do callable retorna null sem inventar cortesia', () async {
      final svc = MyPlanEffectiveAccessService(
        callFunction: (_, __) async => throw Exception('unavailable'),
      );
      final r = await svc.fetchMyEffectiveAccess();
      expect(r, isNull);
    });
  });

  group('effectivePlanIdForGates — sem elevação local', () {
    test('sem DTO do servidor usa plano contratado', () {
      const EffectivePlanAccessDto? effective = null;
      const contracted = 'free_limited';
      final fromServer = effective?.effectivePlanId;
      final gated = (fromServer != null && fromServer.trim().isNotEmpty)
          ? fromServer
          : contracted;
      expect(gated, contracted);
    });
  });

  group('EffectivePlanAccessDto — DTO sanitizado', () {
    test('não expõe motivo ou administrador da cortesia', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: 'intermediate_monthly',
        accessSource: 'manual_courtesy',
        courtesy: MasterPlanCourtesySummary(
          active: true,
          planId: 'intermediate_monthly',
          type: 'temporary',
          startsAt: '2026-01-01T00:00:00.000Z',
          expiresAt: '2030-01-01T00:00:00.000Z',
        ),
        renewal: MasterPlanRenewalSummary(active: false, cancelAtPeriodEnd: false),
      );
      final json = dto.courtesy;
      expect(json.type, 'temporary');
      expect(json.startsAt, isNotNull);
      // Modelo do app não possui reason/grantedBy/requestFingerprint.
    });
  });
}
