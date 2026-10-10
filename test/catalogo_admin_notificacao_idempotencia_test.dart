// M3.6.5 — idempotência/ownership de notificação de sorteio no fluxo admin.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/email_service.dart';
import 'package:master_palm/services/pos_pagamento_service.dart';

void main() {
  group('M3.6.5 NOTIF2 — notificação de sorteio', () {
    test('NOTIF2-1: participação canônica omite sorteio no PosPagamento', () {
      expect(
        PosPagamentoService.deveOmitirNumeroSorteNotificacaoCliente(
          participacaoCanonica: true,
        ),
        isTrue,
      );
      expect(
        PosPagamentoService.deveOmitirNumeroSorteNotificacaoCliente(
          participacaoCanonica: false,
        ),
        isFalse,
      );
    });

    test('NOTIF2-2: email sem sorteio não envia número canônico duplicado', () {
      final payload = EmailService.payloadConfirmacaoPedido(
        lojaId: 'loja-t',
        vendaId: 'v-1',
      );

      expect(payload.containsKey('luckyNumber'), isFalse);
      expect(payload.containsKey('participationId'), isFalse);
      expect(payload['emailType'], 'order_confirmation');
    });

    test('NOTIF2-6: participação validada pede bloco de sorteio ao servidor', () {
      const numeroB = '59263';
      final payload = EmailService.payloadConfirmacaoPedido(
        lojaId: 'loja-t',
        vendaId: 'v-2',
        camposSorteio: {
          'campaignId': 'camp',
          'participationId': 'venda_v-2',
          'luckyNumber': numeroB,
        },
      );

      expect(payload['luckyNumber'], numeroB);
      expect(payload['participationId'], 'venda_v-2');
    });

    test('NOTIF2-3/5: gate é determinístico por participação canônica', () {
      final omit1 = PosPagamentoService.deveOmitirNumeroSorteNotificacaoCliente(
        participacaoCanonica: true,
      );
      final omit2 = PosPagamentoService.deveOmitirNumeroSorteNotificacaoCliente(
        participacaoCanonica: true,
      );
      expect(omit1, omit2);
      expect(omit1, isTrue);
    });

    test('NOTIF2-12: cupom roleta permanece no email operacional (lido do pedido)', () {
      final contrato =
          File('functions/src/emailContracts.js').readAsStringSync();
      expect(contrato, contains('cupomRoleta: pedido.cupomRoleta'));
      expect(contrato, contains('Você também ganhou na Roleta da Sorte!'));
    });
  });
}
