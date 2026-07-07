// M3.6.5 — idempotência/ownership de notificação de sorteio no fluxo admin.

import 'package:flutter_test/flutter_test.dart';
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

    test('NOTIF2-2: email sem sorteio não expõe número canônico duplicado', () {
      const numeroA = '48152';
      final html = PosPagamentoService.montarEmailHtmlNotificacaoCliente(
        nome: 'Cliente',
        lojaNome: 'Loja Teste',
        numeroSorte: numeroA,
        valorTotal: 120,
        incluirNumeroSorte: false,
      );

      expect(html, isNot(contains(numeroA)));
      expect(html, isNot(contains('Número da Sorte')));
      expect(html, contains('Pedido confirmado'));
    });

    test('NOTIF2-6: legado sem Engine mantém bloco de sorteio no email', () {
      const numeroB = '59263';
      final html = PosPagamentoService.montarEmailHtmlNotificacaoCliente(
        nome: 'Cliente',
        lojaNome: 'Loja Teste',
        numeroSorte: numeroB,
        valorTotal: 80,
        incluirNumeroSorte: true,
      );

      expect(html, contains(numeroB));
      expect(html, contains('Número da Sorte'));
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

    test('NOTIF2-12: cupom roleta permanece no email operacional', () {
      final html = PosPagamentoService.montarEmailHtmlNotificacaoCliente(
        nome: 'Cliente',
        lojaNome: 'Loja',
        numeroSorte: '11111',
        valorTotal: 50,
        incluirNumeroSorte: false,
        cupomRoletaCodigo: 'ROLETA10',
        cupomRoletaDesconto: 10,
      );

      expect(html, contains('ROLETA10'));
      expect(html, isNot(contains('11111')));
    });
  });
}
