// M3.7 — e-mail de número da sorte (CampaignEngine vs sendEmail CF).

import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';

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
    test('RED-R1: sendEmail HTTP exportada em functions/index.js', () {
      expect(functionsIndex, contains('export const sendEmail = onRequest'));
      expect(functionsIndex, contains('Parâmetros obrigatórios: to, subject, html ou text'));
    });

    test('GREEN-C1: payload campanha alinha chaves com PosPagamento', () {
      final conteudo = CampaignEngineService.montarConteudoEmailParticipacao(
        clienteNome: 'Lara',
        numero: _numero,
        campanhaNome: 'Campanha Borboleta',
        nomeLoja: 'Nathy Pratas',
      );

      final payload = CampaignEngineService.montarPayloadSendEmailCf(
        to: 'lara@test.com',
        subject: conteudo.assunto,
        html: conteudo.html,
      );

      expect(payload.keys.toSet(), equals({'to', 'subject', 'html'}));
      expect(posPagamentoSrc, contains("'to': destinatario"));
      expect(posPagamentoSrc, contains("'subject': assunto"));
      expect(posPagamentoSrc, contains("'html': htmlBody"));

      final json = jsonEncode(payload);
      expect(json, contains('lara@test.com'));
      expect(json, contains(_numero));
    });

    test('GREEN-C2: HTML campanha contém número da sorte', () {
      final conteudo = CampaignEngineService.montarConteudoEmailParticipacao(
        clienteNome: 'Lara',
        numero: _numero,
        campanhaNome: 'Campanha Borboleta',
        nomeLoja: 'Nathy Pratas',
      );

      expect(conteudo.html, contains(_numero));
      expect(conteudo.assunto, contains('Campanha Borboleta'));
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
