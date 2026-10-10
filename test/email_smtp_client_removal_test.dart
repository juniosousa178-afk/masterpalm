// P0 — app/web sem credencial SMTP; todo e-mail passa pelo `sendEmail` tipado e autenticado.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/carrinho_abandonado_service.dart';
import 'package:master_palm/services/email_service.dart';

const _loja = 'loja-smtp';

Iterable<File> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  tearDown(() {
    EmailService.debugEnviarOverride = null;
    CampaignEngineService.debugFirestoreOverride = null;
    CampaignEngineService.debugEnviarWhatsAppOverride = null;
  });

  group('SMTP fora do cliente', () {
    test('nenhum código do app usa mailer / SmtpServer / credencial SMTP', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('mailer:')));
      for (final f in _dartFiles('lib')) {
        final src = f.readAsStringSync();
        expect(src, isNot(contains('package:mailer')), reason: f.path);
        expect(src, isNot(contains('SmtpServer')), reason: f.path);
        expect(src, isNot(contains('smtpSenha')), reason: f.path);
        expect(src, isNot(contains('EmailService.enviarEmail')), reason: f.path);
      }
      expect(File('lib/services/pedido_cliente_email_service.dart').existsSync(), isFalse);
    });

    test('EmailService envia ID token e nunca conteúdo cru', () {
      final src = File('lib/services/email_service.dart').readAsStringSync();
      expect(src, contains("'Authorization': 'Bearer \$token'"));
      for (final p in [
        EmailService.payloadConfirmacaoPedido(lojaId: _loja, vendaId: 'v'),
        EmailService.payloadParticipacaoSorteio({'lojaId': _loja}),
        EmailService.payloadLembreteCarrinho(lojaId: _loja, cartId: 'c'),
      ]) {
        expect(p.keys, isNot(contains('html')));
        expect(p.keys, isNot(contains('subject')));
        expect(p.keys, isNot(contains('text')));
        expect(p['emailType'], isNotEmpty);
      }
    });

    test('reset de senha do cliente usa a callable em todas as plataformas', () {
      final src = File('lib/services/cliente_auth_service.dart').readAsStringSync();
      expect(src, isNot(contains('EmailService')));
      expect(src, contains("httpsCallable('solicitarRedefinicaoSenhaCatalogo')"));
    });

    test('foiEnviado só aceita sent=true com HTTP 200', () {
      expect(EmailService.foiEnviado(200, '{"ok":true,"sent":true}'), isTrue);
      expect(EmailService.foiEnviado(200, '{"ok":true,"sent":false,"duplicate":true}'), isFalse);
      expect(EmailService.foiEnviado(200, '{"ok":false,"sent":false,"code":"RAFFLE_NOT_ACTIVE"}'), isFalse);
      expect(EmailService.foiEnviado(401, '{"sent":true}'), isFalse);
      expect(EmailService.foiEnviado(200, 'x'), isFalse);
    });
  });

  group('fluxos usam o contrato tipado', () {
    test('CampaignEngine envia raffle_participation; recusa não marca e-mail enviado', () async {
      final fs = FakeFirebaseFirestore();
      CampaignEngineService.debugFirestoreOverride = fs;
      CampaignEngineService.debugEnviarWhatsAppOverride = ({
        required telefone,
        required clienteNome,
        required numero,
        required campanhaNome,
        dataSorteio,
        required nomeLoja,
      }) async {};
      final ref = fs
          .collection('lojas')
          .doc(_loja)
          .collection('campanhas_sorteio')
          .doc('camp')
          .collection('participantes')
          .doc('venda_v-1');
      await ref.set({'numeroSorte': '48152', 'vendaId': 'v-1'});

      final enviados = <Map<String, String>>[];
      EmailService.debugEnviarOverride = (p) async {
        enviados.add(p);
        return (
          statusCode: 200,
          body: '{"ok":false,"sent":false,"code":"RAFFLE_NOT_ACTIVE"}',
        );
      };

      await CampaignEngineService.executarEnvioMensagensParticipacao(
        lojaId: _loja,
        campanhaId: 'camp',
        participacaoId: 'venda_v-1',
        numero: '48152',
        clienteNome: 'Lara',
        email: 'lara@example.test',
        campanhaNome: 'Campanha',
        nomeLoja: 'Loja',
      );

      expect(enviados, hasLength(1));
      expect(enviados.single, {
        'emailType': 'raffle_participation',
        'lojaId': _loja,
        'saleId': 'v-1',
        'campaignId': 'camp',
        'participationId': 'venda_v-1',
        'luckyNumber': '48152',
      });
      expect((await ref.get()).data()?['mensagemEnviadaEmail'], isNot(true));
    });

    test('carrinho do catálogo envia abandoned_cart_reminder e mostra o cooldown', () async {
      Map<String, String>? enviado;
      EmailService.debugEnviarOverride = (p) async {
        enviado = p;
        return (
          statusCode: 429,
          body: '{"ok":false,"sent":false,"code":"EMAIL_COOLDOWN"}',
        );
      };

      final r = await CarrinhoAbandonadoService.enviarLembreteEmailCatalogo(
        lojaId: _loja,
        cartId: 'cart-1',
        emailDestino: 'Ana@Example.test',
        linkRecuperacao: 'https://app.mastepalm.com.br/loja/$_loja?cart=cart-1',
      );

      expect(r.ok, isFalse);
      expect(r.mensagem, contains('há pouco'));
      expect(enviado, {
        'emailType': 'abandoned_cart_reminder',
        'lojaId': _loja,
        'cartId': 'cart-1',
        'to': 'ana@example.test',
        'link': 'https://app.mastepalm.com.br/loja/$_loja?cart=cart-1',
      });
    });
  });
}
