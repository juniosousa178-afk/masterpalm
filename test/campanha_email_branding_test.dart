// M3.7-HOMOLOG-FINAL — H9 branding e-mail campanha (EMAILBRAND-1…5)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/email_service.dart';

const _lojaId = 'nathy-pratas-e-folheados';
const _nomeLoja = 'Nathy Pratas e Folheados';

void main() {
  final contrato = File('functions/src/emailContracts.js').readAsStringSync();
  final campaignSrc =
      File('lib/services/campaign_engine_service.dart').readAsStringSync();

  group('EMAILBRAND — identidade da loja no remetente', () {
    test('EMAILBRAND-1: payload inclui lojaId para CF resolver nome', () {
      final payload = EmailService.payloadParticipacaoSorteio({
        'lojaId': _lojaId,
        'saleId': 'v-1',
        'campaignId': 'c-1',
        'participationId': 'venda_v-1',
        'luckyNumber': '48152',
      });

      expect(payload['lojaId'], _lojaId);
      expect(payload.containsKey('to'), isFalse);
      expect(jsonEncode(payload), contains(_lojaId));
    });

    test('EMAILBRAND-2: loja inexistente usa fallback MasterPalm na CF', () {
      expect(contrato, contains('return "MasterPalm";'));
      expect(contrato, contains('d.nome || d.name'));
      expect(contrato, contains('storeDisplayName(db, colLojas, lojaId)'));
    });

    test('EMAILBRAND-3: CF não confia fromName arbitrário do cliente', () {
      expect(contrato, isNot(contains('body.fromName')));
      expect(contrato, isNot(contains('body.displayName')));
      expect(contrato, contains('from: `"\${plan.send.lojaNome}" <\${smtpUser}>`'));
    });

    test('EMAILBRAND-4: subject e html montados no servidor com dados da campanha', () {
      expect(contrato, contains('Confirmacao de participacao - Campanha \${campanhaNome}'));
      expect(contrato, contains('campanha.nome || campanha.titulo'));
      expect(contrato, contains('Loja: \${escapeHtml(lojaNome)}'));
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
