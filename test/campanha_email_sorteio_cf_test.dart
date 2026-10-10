// M3.7 — e-mail de número da sorte (CampaignEngine vs sendEmail CF).

import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/email_service.dart';

const _lojaId = 'loja-email-sorteio';
const _campanhaId = 'camp-email-1';
const _participacaoId = 'part-email-1';
const _numero = '48152';

void main() {
  final functionsIndex =
      File('functions/index.js').readAsStringSync();
  final posPagamentoSrc =
      File('lib/services/pos_pagamento_service.dart').readAsStringSync();

  group('M3.7 EMAIL-SORTEIO — contrato sendEmail', () {
    test('RED-R1: sendEmail HTTP exportada e tipada em functions/index.js', () {
      expect(functionsIndex, contains('export const sendEmail = onRequest'));
      expect(functionsIndex, contains('handleSendEmailRequest({'));
      expect(functionsIndex, contains('extractBearerTokenFromRequest(req)'));
    });

    test('GREEN-C1: payload campanha alinha chaves com PosPagamento (sem conteúdo cru)', () {
      final campos = {
        'lojaId': _lojaId,
        'saleId': 'venda-1',
        'campaignId': _campanhaId,
        'participationId': _participacaoId,
        'luckyNumber': _numero,
      };
      final payload = EmailService.payloadParticipacaoSorteio(campos);
      expect(
        payload.keys.toSet(),
        equals({'emailType', 'lojaId', 'saleId', 'campaignId', 'participationId', 'luckyNumber'}),
      );
      final posPayload = EmailService.payloadConfirmacaoPedido(
        lojaId: _lojaId,
        vendaId: 'venda-1',
        camposSorteio: campos,
      );
      expect(posPayload['participationId'], payload['participationId']);
      expect(posPagamentoSrc, contains('EmailService.payloadConfirmacaoPedido('));

      final json = jsonEncode(payload);
      expect(json, isNot(contains('lara@test.com')));
      expect(json, contains(_numero));
    });

    test('GREEN-C2: servidor monta o e-mail de campanha com o número persistido', () {
      final contrato =
          File('functions/src/emailContracts.js').readAsStringSync();
      expect(contrato, contains('Confirmacao de participacao - Campanha'));
      expect(contrato, contains('verified.participation?.numeroSorte'));
    });

    test('GREEN-C3: flag mensagemEnviadaEmail só true após envio bem-sucedido', () async {
      final firestore = FakeFirebaseFirestore();
      CampaignEngineService.debugFirestoreOverride = firestore;

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('campanhas_sorteio')
          .doc(_campanhaId)
          .collection('participantes')
          .doc(_participacaoId)
          .set({
        'numeroSorte': _numero,
        'mensagemEnviadaEmail': false,
        'mensagemEnviadaWhatsApp': true,
      });

      var emailCalls = 0;
      CampaignEngineService.debugEnviarEmailOverride = ({
        required email,
        required clienteNome,
        required numero,
        required campanhaNome,
        dataSorteio,
        required nomeLoja,
      }) async {
        emailCalls++;
        throw Exception('simula falha CF/SMTP');
      };

      await CampaignEngineService.executarEnvioMensagensParticipacao(
        lojaId: _lojaId,
        campanhaId: _campanhaId,
        participacaoId: _participacaoId,
        numero: _numero,
        clienteNome: 'Lara',
        telefone: '11999998888',
        email: 'lara@test.com',
        campanhaNome: 'Campanha',
        nomeLoja: _lojaId,
      );

      expect(emailCalls, 1);

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('campanhas_sorteio')
          .doc(_campanhaId)
          .collection('participantes')
          .doc(_participacaoId)
          .get();

      expect(snap.data()?['mensagemEnviadaEmail'], isNot(true));

      CampaignEngineService.debugFirestoreOverride = null;
      CampaignEngineService.debugEnviarEmailOverride = null;
    });
  });
}
