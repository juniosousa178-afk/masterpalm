import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/effective_plan_access.dart';
import 'package:master_palm/core/master_plan_access_models.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  PlanAccessTier tierFromDto(EffectivePlanAccessDto dto) {
    return EffectivePlanAccess.fromDto(dto).effectiveTier;
  }

  group('EffectivePlanAccess — tiers por cortesia', () {
    test('cortesia Pro ativa libera tier Pro', () {
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
      expect(tierFromDto(dto), PlanAccessTier.pro);
    });

    test('cortesia Intermediário não recebe tier Pro', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: 'intermediate_monthly',
        accessSource: 'manual_courtesy',
        courtesy: MasterPlanCourtesySummary(
          active: true,
          planId: 'intermediate_monthly',
        ),
        renewal: MasterPlanRenewalSummary(
          active: false,
          cancelAtPeriodEnd: false,
        ),
      );
      expect(tierFromDto(dto), PlanAccessTier.intermediate);
      expect(
        PlanMatrix.allows(tierFromDto(dto), PlanGateFeature.metasComissoes),
        isFalse,
      );
    });

    test('cortesia expirada no DTO usa plano contratado do servidor', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'free_limited',
        effectivePlanId: 'free_limited',
        accessSource: 'free_limited',
        courtesy: MasterPlanCourtesySummary(active: false),
        renewal: MasterPlanRenewalSummary(
          active: false,
          cancelAtPeriodEnd: false,
        ),
      );
      expect(tierFromDto(dto), PlanAccessTier.freeLimited);
    });

    test('fallback contratado não altera contractedPlanId', () {
      final access = EffectivePlanAccess.fallbackContracted(
        contractedPlanId: 'basic_monthly',
      );
      expect(access.contractedPlanId, PlanId.basicMonthly);
      expect(access.effectivePlanId, PlanId.basicMonthly);
      expect(access.accessSource, 'contracted_fallback');
    });

    test('pago com cancelAtPeriodEnd preserva tier pago no effectivePlanId', () {
      const dto = EffectivePlanAccessDto(
        contractedPlanId: 'pro_monthly',
        effectivePlanId: 'pro_monthly',
        accessSource: 'paid_subscription',
        courtesy: MasterPlanCourtesySummary(active: false),
        renewal: MasterPlanRenewalSummary(
          active: true,
          cancelAtPeriodEnd: true,
        ),
      );
      expect(tierFromDto(dto), PlanAccessTier.pro);
      expect(
        PlanMatrix.allows(tierFromDto(dto), PlanGateFeature.fornecedores),
        isTrue,
      );
    });
  });
}
