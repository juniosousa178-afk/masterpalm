// Regressão: aliases e normalização de plano (compatibilidade).

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  group('PlanosService.normalizePlanId', () {
    test('mensal / anual → pro_monthly / pro_yearly', () {
      expect(PlanosService.normalizePlanId('mensal'), PlanId.proMonthly);
      expect(PlanosService.normalizePlanId('pro_monthly'), PlanId.proMonthly);
      expect(PlanosService.normalizePlanId('anual'), PlanId.proYearly);
      expect(PlanosService.normalizePlanId('pro_yearly'), PlanId.proYearly);
    });

    test('freelight e free_limited → free_limited', () {
      expect(PlanosService.normalizePlanId('freelight'), PlanId.freeLimited);
      expect(PlanosService.normalizePlanId('free_limited'), PlanId.freeLimited);
    });

    test('trial aliases → free_trial_90d ou 30d', () {
      expect(PlanosService.normalizePlanId('trial'), PlanId.freeTrial90d);
      expect(PlanosService.normalizePlanId('free_trial'), PlanId.freeTrial90d);
      expect(PlanosService.normalizePlanId('trial_30d'), PlanId.freeTrial30d);
    });

    test('basic / intermediate mensal', () {
      expect(PlanosService.normalizePlanId('basic'), PlanId.basicMonthly);
      expect(PlanosService.normalizePlanId('intermediate'), PlanId.intermediateMonthly);
    });

    test('desconhecido preserva string lower (passthrough)', () {
      expect(PlanosService.normalizePlanId('Custom_Plan'), 'custom_plan');
    });

    test('lifetime normalizado', () {
      expect(PlanosService.normalizePlanId('lifetime'), PlanId.lifetime);
    });
  });
}
