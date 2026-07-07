import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pre_pedido_confirmacao_eligibility.dart';

const _lojaId = 'loja-admmp-test';
const _prePedidoId = 'pp-admmp-1';

Map<String, dynamic> _pendenteBase() => {
      'id': _prePedidoId,
      'status': 'pendente',
      'statusPagamento': 'pendente',
      'pagamento': 'Mercado Pago',
      'itens': [],
    };

void main() {
  group('ADMMP — PrePedidoConfirmacaoEligibility.evaluateMap', () {
    test('ADMMP-1 pendente sem paidAt é elegível', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap(_pendenteBase());
      expect(r.isEligible, isTrue);
      expect(r.reason, PrePedidoConfirmacaoBlockReason.eligible);
    });

    test('ADMMP-2 paidAt presente bloqueia', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap({
        ..._pendenteBase(),
        'paidAt': Timestamp.now(),
        'paymentId': 'pay-1',
        'status': 'paid',
        'statusPagamento': 'aprovado',
      });
      expect(r.isEligible, isFalse);
      expect(r.reason,
          PrePedidoConfirmacaoBlockReason.alreadyPaidByMercadoPago);
    });

    test('ADMMP-3 paymentId + statusPagamento aprovado bloqueia', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap({
        ..._pendenteBase(),
        'paymentId': 'pay-99',
        'statusPagamento': 'aprovado',
      });
      expect(r.isEligible, isFalse);
      expect(r.reason,
          PrePedidoConfirmacaoBlockReason.alreadyPaidByMercadoPago);
    });

    test('ADMMP-4 pagamento pending sem paidAt permanece elegível', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap({
        ..._pendenteBase(),
        'statusPagamento': 'pendente',
      });
      expect(r.isEligible, isTrue);
    });

    test('ADMMP-5 rejected/cancelled sem paidAt permanece elegível', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap({
        ..._pendenteBase(),
        'statusPagamento': 'rejected',
        'mpPaymentStatus': 'rejected',
      });
      expect(r.isEligible, isTrue);
    });

    test('ADMMP-6 estado pago MP continua bloqueando após retry lógico', () {
      final paid = {
        ..._pendenteBase(),
        'paidAt': Timestamp.now(),
        'paymentId': 'pay-dup',
        'status': 'paid',
        'statusPagamento': 'aprovado',
      };
      expect(
        PrePedidoConfirmacaoEligibility.evaluateMap(paid).isEligible,
        isFalse,
      );
      expect(
        PrePedidoConfirmacaoEligibility.evaluateMap(paid).isEligible,
        isFalse,
      );
    });

    test('ADMMP-7 dois admins — mesma avaliação bloqueia ambos', () {
      final paid = {
        ..._pendenteBase(),
        'paidAt': Timestamp.now(),
        'paymentId': 'pay-7',
        'status': 'paid',
      };
      final a = PrePedidoConfirmacaoEligibility.evaluateMap(paid);
      final b = PrePedidoConfirmacaoEligibility.evaluateMap(paid);
      expect(a.isEligible, isFalse);
      expect(b.isEligible, isFalse);
    });

    test('ADMMP-8 já confirmado bloqueia sem MP', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap({
        ..._pendenteBase(),
        'status': 'confirmado',
        'vendaId': 'hive-1',
      });
      expect(r.isEligible, isFalse);
      expect(r.reason, PrePedidoConfirmacaoBlockReason.alreadyConfirmed);
    });

    test('ADMMP-9 mapa stale pendente vs canônico pago — evaluateMap no canônico bloqueia', () {
      final stale = _pendenteBase();
      final fresh = {
        ..._pendenteBase(),
        'paidAt': Timestamp.now(),
        'paymentId': 'pay-9',
        'status': 'paid',
        'statusPagamento': 'aprovado',
      };
      expect(PrePedidoConfirmacaoEligibility.evaluateMap(stale).isEligible,
          isTrue);
      expect(PrePedidoConfirmacaoEligibility.evaluateMap(fresh).isEligible,
          isFalse);
    });

    test('ADMMP-10 snapshot UI stale não decide — serviço usa Firestore', () async {
      final fs = FakeFirebaseFirestore();
      await fs
          .collection('lojas')
          .doc(_lojaId)
          .collection('pre_pedidos')
          .doc(_prePedidoId)
          .set({
        'status': 'paid',
        'paidAt': Timestamp.now(),
        'paymentId': 'pay-10',
        'statusPagamento': 'aprovado',
      });

      final svc = PrePedidoConfirmacaoEligibilityService(firestore: fs);
      final staleUi = _pendenteBase();
      expect(
        PrePedidoConfirmacaoEligibility.evaluateMap(staleUi).isEligible,
        isTrue,
      );

      final loaded = await svc.loadAndEvaluate(
        lojaId: _lojaId,
        prePedidoId: _prePedidoId,
      );
      expect(loaded.isEligible, isFalse);
      expect(loaded.reason,
          PrePedidoConfirmacaoBlockReason.alreadyPaidByMercadoPago);
    });

    test('ADMMP-11 documento ausente — fail-closed', () async {
      final fs = FakeFirebaseFirestore();
      final svc = PrePedidoConfirmacaoEligibilityService(firestore: fs);
      final r = await svc.loadAndEvaluate(
        lojaId: _lojaId,
        prePedidoId: 'inexistente',
      );
      expect(r.isEligible, isFalse);
      expect(r.reason, PrePedidoConfirmacaoBlockReason.documentNotFound);
    });

    test('ADMMP-12 prePedidoId vazio', () {
      final r = PrePedidoConfirmacaoEligibility.evaluateMap({
        'status': 'pendente',
      });
      expect(r.isEligible, isFalse);
      expect(r.reason, PrePedidoConfirmacaoBlockReason.prePedidoIdMissing);
    });
  });

  group('ADMMP — guard estrutural em pre_pedidos_screen', () {
    test('registrarVendaMulti precedido por elegibilidade remota', () {
      final src =
          File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      final iConfirmar = src.indexOf('Future<void> _confirmarPedido');
      expect(iConfirmar, greaterThan(0));
      final trecho = src.substring(iConfirmar);
      final iElig = trecho.indexOf('loadAndEvaluate');
      final iVenda = trecho.indexOf('VendasService.registrarVendaMulti');
      expect(iElig, greaterThan(0));
      expect(iVenda, greaterThan(iElig));
    });
  });
}
