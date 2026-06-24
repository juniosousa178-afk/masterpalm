import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  group('normalizePlanIdForAccess', () {
    test('pro e pro_monthly resolvem para o mesmo tier', () {
      expect(
        PlanosService.normalizePlanIdForAccess('pro'),
        PlanosService.normalizePlanIdForAccess('pro_monthly'),
      );
    });

    test('intermediate e intermediate_monthly resolvem igual', () {
      expect(
        PlanosService.normalizePlanIdForAccess('intermediate'),
        PlanosService.normalizePlanIdForAccess('intermediate_monthly'),
      );
    });

    test('plano desconhecido não eleva acesso', () {
      expect(
        PlanosService.normalizePlanIdForAccess('plano_inventado_xyz'),
        PlanId.freeLimited,
      );
    });
  });

  group('resolveEffectivePlanIdForGates', () {
    test('cortesia Pro libera effectivePlanId pro_monthly', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: 'pro_monthly',
        accessSource: 'manual_courtesy',
        courtesy: MasterPlanCourtesySummary(
          active: true,
          planId: 'pro_monthly',
        ),
        renewal: MasterPlanRenewalSummary(
          active: false,
          cancelAtPeriodEnd: false,
        ),
      );
      expect(
        PlanosService.resolveEffectivePlanIdForGates(
          serverDto: dto,
          contractedPlanId: 'free_limited',
        ),
        PlanId.proMonthly,
      );
    });

    test('falha do callable mantém plano contratado', () {
      expect(
        PlanosService.resolveEffectivePlanIdForGates(
          serverDto: null,
          contractedPlanId: 'free_limited',
        ),
        PlanId.freeLimited,
      );
    });

    test('não inventa cortesia quando servidor retorna null', () {
      expect(
        PlanosService.resolveEffectivePlanIdForGates(
          serverDto: null,
          contractedPlanId: 'basic_monthly',
        ),
        PlanId.basicMonthly,
      );
    });

    test('servidor vazio não eleva acima do contratado', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: '',
        accessSource: 'free_limited',
        courtesy: MasterPlanCourtesySummary(active: false),
        renewal: MasterPlanRenewalSummary(
          active: false,
          cancelAtPeriodEnd: false,
        ),
      );
      expect(
        PlanosService.resolveEffectivePlanIdForGates(
          serverDto: dto,
          contractedPlanId: 'free_limited',
        ),
        PlanId.freeLimited,
      );
    });
  });
}
