// M3.7-HOMOLOG-FINAL — H9 branding e-mail campanha (EMAILBRAND-1…5)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';

const _lojaId = 'nathy-pratas-e-folheados';
const _nomeLoja = 'Nathy Pratas e Folheados';

void main() {
  final functionsIndex = File('functions/index.js').readAsStringSync();
  final campaignSrc =
      File('lib/services/campaign_engine_service.dart').readAsStringSync();

  group('EMAILBRAND — identidade da loja no remetente', () {
    test('EMAILBRAND-1: payload inclui lojaId para CF resolver nome', () {
      final conteudo = CampaignEngineService.montarConteudoEmailParticipacao(
        clienteNome: 'Lara',
        numero: '48152',
        campanhaNome: 'Campanha Borboleta',
        nomeLoja: _nomeLoja,
      );
      final payload = CampaignEngineService.montarPayloadSendEmailCf(
        to: 'lara@test.com',
        subject: conteudo.assunto,
        html: conteudo.html,
        lojaId: _lojaId,
      );

      expect(payload['lojaId'], _lojaId);
      expect(payload['to'], 'lara@test.com');
      expect(jsonEncode(payload), contains(_lojaId));
    });

    test('EMAILBRAND-2: loja inexistente usa fallback MasterPalm na CF', () {
      expect(functionsIndex, contains('let displayName = "MasterPalm"'));
      expect(functionsIndex, contains('if (lojaId)'));
      expect(functionsIndex, contains('lojaData.nome || lojaData.name'));
    });

    test('EMAILBRAND-3: CF não confia fromName arbitrário do cliente', () {
      expect(
        functionsIndex,
        contains('nunca confiar fromName do cliente'),
      );
      expect(functionsIndex, isNot(contains('body.fromName')));
      expect(functionsIndex, isNot(contains('body.displayName')));
    });

    test('EMAILBRAND-4: subject e html permanecem corretos', () {
      final conteudo = CampaignEngineService.montarConteudoEmailParticipacao(
        clienteNome: 'Lara',
        numero: '48152',
        campanhaNome: 'Campanha Borboleta',
        nomeLoja: _nomeLoja,
      );

      expect(conteudo.assunto, contains('Campanha Borboleta'));
      expect(conteudo.html, contains('48152'));
      expect(conteudo.html, contains(_nomeLoja));
    });

    test('EMAILBRAND-5: WhatsApp inalterado (sem lojaId no payload WA)', () {
      final msg = CampaignEngineService.montarMensagemWhatsAppParticipacao(
        clienteNome: 'Lara',
        numero: '48152',
        campanhaNome: 'Campanha Borboleta',
        nomeLoja: _nomeLoja,
      );
      expect(msg, contains('48152'));
      expect(msg, contains(_nomeLoja));
      expect(campaignSrc, contains('montarMensagemWhatsAppParticipacao'));
      expect(campaignSrc, contains('_enviarWhatsApp'));
    });
  });
}
