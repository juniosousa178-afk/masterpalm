import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/plan_matrix.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/limits_guard.dart';
import 'package:master_palm/services/planos_service.dart';

void main() {
  group('VendaLimitCheckResult.userMessage', () {
    test('checkFailed não menciona plano Free', () {
      const r = VendaLimitCheckResult(status: VendaLimitStatus.checkFailed);
      expect(r.userMessage(), contains('verificar o limite'));
      expect(r.userMessage().toLowerCase(), isNot(contains('plano free')));
    });

    test('blockedAtLimit usa rótulo do plano efetivo', () {
      const r = VendaLimitCheckResult(
        status: VendaLimitStatus.blockedAtLimit,
        planId: PlanId.intermediateMonthly,
        vendasNoMes: 500,
        limiteMensal: 500,
      );
      expect(r.userMessage(), contains('Intermediário'));
      expect(r.userMessage(), isNot(contains('plano Free')));
    });
  });

  group('LimitsGuard.checkVendaLimit', () {
    late FakeFirebaseFirestore firestore;
    const lojaId = 'loja-limite-venda-test';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      LimitsGuard.debugFirestoreOverride = firestore;
    });

    tearDown(() {
      LimitsGuard.debugFirestoreOverride = null;
      LimitsGuard.debugEffectivePlanIdOverride = null;
    });

    Future<void> seedVendasMesAtual(int count) async {
      final col = firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueVendasCol);
      final when = DateTime.now();
      for (var i = 0; i < count; i++) {
        await col.add({
          'createdAt': Timestamp.fromDate(when),
          'status': 'concluida',
        });
      }
    }

    test('free_limited abaixo do limite libera', () async {
      await seedVendasMesAtual(5);
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: PlanId.freeLimited,
      );
      expect(r.status, VendaLimitStatus.allowed);
      expect(r.vendasNoMes, 5);
      expect(r.limiteMensal, PlanMatrix.limitsForPlanId(PlanId.freeLimited).vendasMes);
    });

    test('free_limited exatamente no limite bloqueia', () async {
      await seedVendasMesAtual(10);
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: PlanId.freeLimited,
      );
      expect(r.status, VendaLimitStatus.blockedAtLimit);
      expect(r.userMessage(), contains('Gratuito limitado'));
    });

    test('free_limited acima do limite bloqueia', () async {
      await seedVendasMesAtual(11);
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: PlanId.freeLimited,
      );
      expect(r.status, VendaLimitStatus.blockedAtLimit);
    });

    test('plano pro efetivo libera acima de 10 vendas no mês', () async {
      await seedVendasMesAtual(25);
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: PlanId.proMonthly,
      );
      expect(r.status, VendaLimitStatus.allowed);
    });

    test('trial pleno libera acima de 10 vendas no mês', () async {
      await seedVendasMesAtual(25);
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: PlanId.freeTrial30d,
      );
      expect(r.status, VendaLimitStatus.allowed);
    });

    test('checkFailed bloqueia sem liberar venda', () {
      const r = VendaLimitCheckResult(status: VendaLimitStatus.checkFailed);
      expect(r.canAdd, isFalse);
      expect(r.userMessage().toLowerCase(), isNot(contains('plano free')));
    });

    test('plano indeterminado (vazio) retorna checkFailed', () async {
      await seedVendasMesAtual(99);
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: '',
      );
      expect(r.status, VendaLimitStatus.checkFailed);
      expect(r.canAdd, isFalse);
    });

    test('plano nulo retorna checkFailed', () async {
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: null,
      );
      expect(r.status, VendaLimitStatus.checkFailed);
    });

    test('plano inválido retorna checkFailed', () async {
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: 'plano_inexistente_xyz',
      );
      expect(r.status, VendaLimitStatus.checkFailed);
    });

    test('callable/rede falha retorna checkFailed', () async {
      LimitsGuard.debugEffectivePlanIdOverride = () async {
        throw Exception('rede indisponível');
      };
      final r = await LimitsGuard().checkVendaLimit(lojaId);
      expect(r.status, VendaLimitStatus.checkFailed);
    });

    test('plano efetivo ausente retorna checkFailed', () async {
      LimitsGuard.debugEffectivePlanIdOverride = () async => null;
      final r = await LimitsGuard().checkVendaLimit(lojaId);
      expect(r.status, VendaLimitStatus.checkFailed);
    });

    test('erro Firestore na contagem retorna checkFailed, não blockedAtLimit', () async {
      LimitsGuard.debugFirestoreOverride = _FirestoreCountThrows();
      final r = await LimitsGuard().checkVendaLimit(
        lojaId,
        planId: PlanId.freeLimited,
      );
      expect(r.status, VendaLimitStatus.checkFailed);
      expect(r.status, isNot(VendaLimitStatus.blockedAtLimit));
      expect(r.userMessage().toLowerCase(), isNot(contains('atingido')));
    });
  });
}

/// Firestore mínimo que falha na consulta de contagem (rede/indisponível).
class _FirestoreCountThrows extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'network error',
    );
  }
}
