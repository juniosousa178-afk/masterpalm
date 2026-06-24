import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/planos_service.dart';

/// Espelha a lógica da Home: gates usam tier do effectivePlanId, não do contratado.
PlanAccessTier homeMenuTierForEffectivePlan(String effectivePlanId) {
  return PlanMatrix.tierForPlanId(
    PlanosService.normalizePlanIdForAccess(effectivePlanId),
  );
}

void main() {
  const proFeatures = [
    PlanGateFeature.metasComissoes,
  ];

  const intermediateFeatures = [
    PlanGateFeature.fornecedores,
    PlanGateFeature.relatorioFinanceiroDetalhado,
    PlanGateFeature.financeiroLancamentos,
    PlanGateFeature.relatoriosFinanceirosHub,
  ];

  group('Home — cards principais (acesso efetivo)', () {
    test('1–4. Pro contratado pago libera Fornecedores, Relatórios, Gestão e Metas hub', () {
      final tier = homeMenuTierForEffectivePlan(PlanId.proMonthly);
      for (final f in intermediateFeatures) {
        expect(PlanMatrix.allows(tier, f), isTrue, reason: '$f');
      }
      for (final f in proFeatures) {
        expect(PlanMatrix.allows(tier, f), isTrue, reason: '$f');
      }
    });

    test('5. Gratuito com cortesia Pro libera os quatro recursos intermediários', () {
      final tier = homeMenuTierForEffectivePlan(PlanId.proMonthly);
      for (final f in intermediateFeatures) {
        expect(PlanMatrix.allows(tier, f), isTrue, reason: '$f');
      }
    });

    test('6. Gratuito sem cortesia mantém os quatro bloqueados', () {
      final tier = homeMenuTierForEffectivePlan(PlanId.freeLimited);
      for (final f in intermediateFeatures) {
        expect(PlanMatrix.allows(tier, f), isFalse, reason: '$f');
      }
    });

    test('7. Intermediário por cortesia não recebe benefícios exclusivos de Pro', () {
      final tier = homeMenuTierForEffectivePlan(PlanId.intermediateMonthly);
      for (final f in intermediateFeatures) {
        expect(PlanMatrix.allows(tier, f), isTrue, reason: '$f');
      }
      for (final f in proFeatures) {
        expect(PlanMatrix.allows(tier, f), isFalse, reason: '$f');
      }
    });

    test('contratado free_limited com effective Pro difere do contratado isolado', () {
      final contractedTier = homeMenuTierForEffectivePlan(PlanId.freeLimited);
      final courtesyProTier = homeMenuTierForEffectivePlan(PlanId.proMonthly);
      expect(
        PlanMatrix.allows(contractedTier, PlanGateFeature.fornecedores),
        isFalse,
      );
      expect(
        PlanMatrix.allows(courtesyProTier, PlanGateFeature.fornecedores),
        isTrue,
      );
    });
  });
}
