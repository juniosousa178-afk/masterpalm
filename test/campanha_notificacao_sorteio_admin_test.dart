// M3.7 — notificação de número da sorte no confirm admin + campanha ativa.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/pos_pagamento_service.dart';

void main() {
  final engineSrc =
      File('lib/services/campaign_engine_service.dart').readAsStringSync();

  group('M3.7 NOTIF-ADMIN — ownership sorteio confirm admin', () {
    test('NOTIF-ADMIN-1: participação canônica omite bloco sorteio no PosPagamento', () {
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

    test('NOTIF-ADMIN-2: email operacional sem sorteio não expõe número', () {
      const numero = '48152';
      final html = PosPagamentoService.montarEmailHtmlNotificacaoCliente(
        nome: 'Lara',
        lojaNome: 'Loja',
        numeroSorte: numero,
        valorTotal: 151.91,
        incluirNumeroSorte: false,
      );

      expect(html, isNot(contains(numero)));
      expect(html, contains('Pedido confirmado'));
    });

    test('NOTIF-ADMIN-3: CampaignEngine usa Cloud Functions para envio real', () {
      expect(engineSrc, contains('sendWhatsAppOrderConfirmation'));
      expect(engineSrc, contains('sendEmail'));
      expect(engineSrc, contains('WhatsApp CF enviado'));
    });

    test('NOTIF-ADMIN-4: mensagem de campanha inclui número da sorte', () {
      final msg = CampaignEngineService.montarMensagemWhatsAppParticipacao(
        clienteNome: 'Lara',
        numero: '54321',
        campanhaNome: 'Campanha Borboleta',
        nomeLoja: 'Nathy Pratas',
      );

      expect(msg, contains('54321'));
      expect(msg, contains('Numero da sorte'));
    });

    test('NOTIF-ADMIN-5: resolver canais exige telefone/email não vazios', () {
      final semContato = CampaignEngineService.resolverCanaisNotificacaoParticipacao(
        mensagemEnviadaWhatsApp: false,
        mensagemEnviadaEmail: false,
        temTelefone: false,
        temEmail: false,
      );
      expect(semContato.enviarWhatsapp, isFalse);
      expect(semContato.enviarEmail, isFalse);

      final comContato = CampaignEngineService.resolverCanaisNotificacaoParticipacao(
        mensagemEnviadaWhatsApp: false,
        mensagemEnviadaEmail: false,
        temTelefone: true,
        temEmail: true,
      );
      expect(comContato.enviarWhatsapp, isTrue);
      expect(comContato.enviarEmail, isTrue);
    });
  });
}
