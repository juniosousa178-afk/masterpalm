// M3.6.6 — idempotência de notificação de sorteio por canal (participante canônico).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';

const _lojaId = 'loja-marker-test';
const _campanhaId = 'camp-marker-1';
const _participacaoId = 'part-marker-1';
const _numero = '48152';

Future<void> _seedParticipante(
  FakeFirebaseFirestore fs, {
  bool mensagemEnviadaEmail = false,
  bool mensagemEnviadaWhatsApp = false,
}) async {
  await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('campanhas_sorteio')
      .doc(_campanhaId)
      .collection('participantes')
      .doc(_participacaoId)
      .set({
    'numeroSorte': _numero,
    'pedidoId': 'venda-marker-1',
    'vendaId': 'venda-marker-1',
    'mensagemEnviadaEmail': mensagemEnviadaEmail,
    'mensagemEnviadaWhatsApp': mensagemEnviadaWhatsApp,
  });
}

void main() {
  late FakeFirebaseFirestore firestore;
  int emailCalls = 0;
  int waCalls = 0;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    emailCalls = 0;
    waCalls = 0;
    CampaignEngineService.debugFirestoreOverride = firestore;
    CampaignEngineService.debugEnviarEmailOverride = ({
      required email,
      required clienteNome,
      required numero,
      required campanhaNome,
      dataSorteio,
      required nomeLoja,
    }) async {
      emailCalls++;
    };
    CampaignEngineService.debugEnviarWhatsAppOverride = ({
      required telefone,
      required clienteNome,
      required numero,
      required campanhaNome,
      dataSorteio,
      required nomeLoja,
    }) async {
      waCalls++;
    };
  });

  tearDown(() {
    CampaignEngineService.debugFirestoreOverride = null;
    CampaignEngineService.debugEnviarEmailOverride = null;
    CampaignEngineService.debugEnviarWhatsAppOverride = null;
  });

  group('M3.6.6 MARK — notificação idempotente por canal', () {
    test('MARK-1: não reenvia email se flag já indica sent', () async {
      await _seedParticipante(firestore, mensagemEnviadaEmail: true);

      await CampaignEngineService.executarEnvioMensagensParticipacao(
        lojaId: _lojaId,
        campanhaId: _campanhaId,
        participacaoId: _participacaoId,
        numero: _numero,
        clienteNome: 'Cliente',
        telefone: '11999998888',
        email: 'cliente@test.com',
        campanhaNome: 'Campanha',
        nomeLoja: _lojaId,
      );

      expect(emailCalls, 0);
      expect(waCalls, 1);
    });

    test('MARK-2: não reabre WA se flag já indica intent enviado', () async {
      await _seedParticipante(firestore, mensagemEnviadaWhatsApp: true);

      await CampaignEngineService.executarEnvioMensagensParticipacao(
        lojaId: _lojaId,
        campanhaId: _campanhaId,
        participacaoId: _participacaoId,
        numero: _numero,
        clienteNome: 'Cliente',
        telefone: '11999998888',
        email: 'cliente@test.com',
        campanhaNome: 'Campanha',
        nomeLoja: _lojaId,
      );

      expect(waCalls, 0);
      expect(emailCalls, 1);
    });

    test('MARK-3: sem flags envia ambos canais e persiste sent', () async {
      await _seedParticipante(firestore);

      await CampaignEngineService.executarEnvioMensagensParticipacao(
        lojaId: _lojaId,
        campanhaId: _campanhaId,
        participacaoId: _participacaoId,
        numero: _numero,
        clienteNome: 'Cliente',
        telefone: '11999998888',
        email: 'cliente@test.com',
        campanhaNome: 'Campanha',
        nomeLoja: _lojaId,
      );

      expect(emailCalls, 1);
      expect(waCalls, 1);

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('campanhas_sorteio')
          .doc(_campanhaId)
          .collection('participantes')
          .doc(_participacaoId)
          .get();

      expect(snap.data()?['mensagemEnviadaEmail'], isTrue);
      expect(snap.data()?['mensagemEnviadaWhatsApp'], isTrue);
    });

    test('MARK-3 retry: segunda execução não reenvia após flags sent', () async {
      await _seedParticipante(firestore);

      for (var i = 0; i < 2; i++) {
        await CampaignEngineService.executarEnvioMensagensParticipacao(
          lojaId: _lojaId,
          campanhaId: _campanhaId,
          participacaoId: _participacaoId,
          numero: _numero,
          clienteNome: 'Cliente',
          telefone: '11999998888',
          email: 'cliente@test.com',
          campanhaNome: 'Campanha',
          nomeLoja: _lojaId,
        );
      }

      expect(emailCalls, 1);
      expect(waCalls, 1);
    });

    test('resolverCanaisNotificacaoParticipacao — MARK-5/6 isolamento', () {
      final r1 = CampaignEngineService.resolverCanaisNotificacaoParticipacao(
        mensagemEnviadaWhatsApp: false,
        mensagemEnviadaEmail: true,
        temTelefone: true,
        temEmail: true,
      );
      expect(r1.enviarWhatsapp, isTrue);
      expect(r1.enviarEmail, isFalse);

      final r2 = CampaignEngineService.resolverCanaisNotificacaoParticipacao(
        mensagemEnviadaWhatsApp: true,
        mensagemEnviadaEmail: true,
        temTelefone: true,
        temEmail: true,
      );
      expect(r2.enviarWhatsapp, isFalse);
      expect(r2.enviarEmail, isFalse);
    });
  });
}
