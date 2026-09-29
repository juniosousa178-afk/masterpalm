import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/planos_service.dart';
import 'package:master_palm/services/pre_pedido_confirmacao_eligibility.dart';

void main() {
  const unrelated = <PlanGateFeature>[
    PlanGateFeature.fornecedores,
    PlanGateFeature.precificacao,
    PlanGateFeature.relatorioFinanceiroDetalhado,
    PlanGateFeature.financeiroLancamentos,
    PlanGateFeature.relatoriosFinanceirosHub,
    PlanGateFeature.carrinhosAbandonados,
    PlanGateFeature.metasComissoes,
    PlanGateFeature.fretesCupons,
  ];

  PlanAccessTier tierOf(String planId) {
    return PlanMatrix.tierForPlanId(PlanosService.normalizePlanId(planId));
  }

  Map<String, dynamic> pendingPreOrder(String id) => {
        'id': id,
        'status': 'pendente',
        'lojaId': 'loja-1',
        'itens': const <Map<String, dynamic>>[],
      };

  test('ids canônicos: free_limited e basic_monthly a 19,99', () {
    expect(PlanId.freeLimited, 'free_limited');
    expect(PlanosService.normalizePlanId('freelight'), PlanId.freeLimited);
    expect(PlanId.basicMonthly, 'basic_monthly');
    expect(PlanosService.normalizePlanId('basic'), PlanId.basicMonthly);
    expect(tierOf('basic'), PlanAccessTier.basic);
    const source = 'lib/screens/planos_screen.dart';
    expect(File(source).readAsStringSync(), contains('_kPrecoBasico = 19.99'));
  });

  test('FREE vê, abre e chega na finalização existente', () {
    final tier = tierOf(PlanId.freeLimited);
    expect(PlanMatrix.canUsePreOrders(tier), isTrue);
    expect(
      PlanMatrix.allows(tier, PlanGateFeature.pedidosPrePedidos),
      isTrue,
    );
    expect(
      HomeModuleRegistry.isPlanLocked(
        HomeModuleRegistry.byId('pre_pedidos')!,
        HomeModuleAccessContext(
          tipoUsuario: 'admin',
          permissoes: const {},
          planTier: tier,
          applyPlanGate: true,
        ),
      ),
      isFalse,
    );
    final ready = PrePedidoConfirmacaoEligibility.evaluateMap(
      pendingPreOrder('pp-free-1'),
    );
    expect(ready.isEligible, isTrue);
  });

  test('plano basic_monthly vê, abre e chega na finalização existente', () {
    final tier = tierOf(PlanId.basicMonthly);
    expect(PlanMatrix.canUsePreOrders(tier), isTrue);
    expect(
      PlanMatrix.allows(tier, PlanGateFeature.pedidosPrePedidos),
      isTrue,
    );
    final ready = PrePedidoConfirmacaoEligibility.evaluateMap(
      pendingPreOrder('pp-basic-1'),
    );
    expect(ready.isEligible, isTrue);
  });

  test('planos superiores continuam com pré-pedidos', () {
    for (final id in [
      PlanId.intermediateMonthly,
      PlanId.proMonthly,
      PlanId.proYearly,
      PlanId.lifetime,
      PlanId.freeTrial30d,
    ]) {
      expect(
        PlanMatrix.canUsePreOrders(tierOf(id)),
        isTrue,
        reason: id,
      );
    }
  });

  test('conta bloqueada, expirada ou suspensa continua sem pré-pedidos', () {
    for (final status in [
      'blocked',
      'expired',
      'suspended',
      'suspensa',
      'cancelada',
    ]) {
      expect(
        PlanMatrix.canUsePreOrders(
          PlanAccessTier.freeLimited,
          accountStatus: status,
        ),
        isFalse,
        reason: status,
      );
      expect(
        PlanMatrix.allows(
          PlanAccessTier.basic,
          PlanGateFeature.pedidosPrePedidos,
          accountStatus: status,
        ),
        isFalse,
        reason: status,
      );
    }
    expect(
      HomeModuleRegistry.isPlanLocked(
        HomeModuleRegistry.byId('pre_pedidos')!,
        HomeModuleAccessContext(
          tipoUsuario: 'admin',
          permissoes: const {},
          planTier: PlanAccessTier.freeLimited,
          applyPlanGate: true,
          accountStatus: 'blocked',
        ),
      ),
      isTrue,
    );
  });

  test('outros recursos premium não acompanham o pré-pedido', () {
    final free = tierOf(PlanId.freeLimited);
    final basic = tierOf(PlanId.basicMonthly);
    for (final feature in unrelated) {
      expect(PlanMatrix.allows(free, feature), isFalse, reason: '$feature free');
      if (feature == PlanGateFeature.metasComissoes ||
          feature == PlanGateFeature.fretesCupons ||
          feature == PlanGateFeature.fornecedores ||
          feature == PlanGateFeature.precificacao ||
          feature == PlanGateFeature.relatoriosFinanceirosHub ||
          feature == PlanGateFeature.carrinhosAbandonados) {
        expect(
          PlanMatrix.allows(basic, feature),
          isFalse,
          reason: '$feature basic',
        );
      }
    }
  });

  test('a tela reusa a finalização atual e não consulta plano', () {
    final src = File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
    final confirmar = src.indexOf('Future<void> _confirmarPedido');
    final trecho = src.substring(confirmar);
    expect(trecho.indexOf('loadAndEvaluate'), greaterThan(0));
    expect(
      trecho.indexOf('VendasService.registrarVendaMulti'),
      greaterThan(trecho.indexOf('loadAndEvaluate')),
    );
    expect(src.contains('PlanMatrix'), isFalse);
    expect(src.contains('PlanGateFeature'), isFalse);
  });
}
