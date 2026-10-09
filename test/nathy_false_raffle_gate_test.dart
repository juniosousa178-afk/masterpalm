// P0 Nathy — sorteio/e-mail sem campanha ativa.
// Sem Firestore real, sem e-mail real.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/campaign_engine_service.dart';
import 'package:master_palm/services/campanha_sorteio_gate.dart';
import 'package:master_palm/services/pos_pagamento_service.dart';

const _loja = 'loja-raffle';
const _outraLoja = 'loja-outra';

Map<String, dynamic> _camp({
  bool ativa = true,
  String? status = 'aberta',
  Duration inicio = const Duration(days: -1),
  Duration fim = const Duration(days: 1),
  bool semDatas = false,
  String? lojaId,
  double valorMinimo = 0,
  Map<String, dynamic> extra = const {},
}) {
  final now = DateTime.now();
  return {
    'nome': 'Campanha',
    'ativa': ativa,
    if (status != null) 'status': status,
    if (!semDatas) 'dataInicio': Timestamp.fromDate(now.add(inicio)),
    if (!semDatas) 'dataFim': Timestamp.fromDate(now.add(fim)),
    if (lojaId != null) 'lojaId': lojaId,
    'valorMinimo': valorMinimo,
    ...extra,
  };
}

CampanhaGateResult _avaliar(List<Map<String, dynamic>> camps) =>
    CampanhaSorteioGate.avaliar(
      [for (var i = 0; i < camps.length; i++) (id: 'c$i', data: camps[i])],
      lojaId: _loja,
      agora: DateTime.now(),
    );

Future<void> _seed(
  FakeFirebaseFirestore fs,
  Map<String, Map<String, dynamic>> camps, {
  String loja = _loja,
}) async {
  for (final e in camps.entries) {
    await fs
        .collection('lojas')
        .doc(loja)
        .collection('campanhas_sorteio')
        .doc(e.key)
        .set(e.value);
  }
}

Future<int> _participantes(FakeFirebaseFirestore fs, String campId,
    {String loja = _loja}) async {
  final s = await fs
      .collection('lojas')
      .doc(loja)
      .collection('campanhas_sorteio')
      .doc(campId)
      .collection('participantes')
      .get();
  return s.docs.length;
}

Future<
    ({
      String? numero,
      bool canonico,
      bool incluirNaNotificacao,
      String? campanhaId,
    })> _resolverPos(String vendaId, {double valor = 100}) =>
    PosPagamentoService.resolverNumeroSorteParaPosPagamento(
      lojaId: _loja,
      vendaId: vendaId,
      estoqueJaBaixado: true,
      customer: const {'nome': 'C', 'email': 'c@example.test'},
      valorTotal: valor,
    );

void main() {
  late FakeFirebaseFirestore fs;

  setUp(() {
    fs = FakeFirebaseFirestore();
    CampanhaSorteioGate.debugFirestoreOverride = fs;
    CampaignEngineService.debugFirestoreOverride = fs;
    PosPagamentoService.debugFirestoreOverride = fs;
    PosPagamentoService.debugBuscarParticipacaoOverride =
        ({required lojaId, required vendaId}) async => null;
    CampaignEngineService.debugEnviarEmailOverride = ({
      required email,
      required clienteNome,
      required numero,
      required campanhaNome,
      dataSorteio,
      required nomeLoja,
    }) async {};
    CampaignEngineService.debugEnviarWhatsAppOverride = ({
      required telefone,
      required clienteNome,
      required numero,
      required campanhaNome,
      dataSorteio,
      required nomeLoja,
    }) async {};
  });

  tearDown(() {
    CampanhaSorteioGate.resetForTests();
    CampaignEngineService.debugEnviarEmailOverride = null;
    CampaignEngineService.debugEnviarWhatsAppOverride = null;
    CampaignEngineService.debugFirestoreOverride = null;
    PosPagamentoService.debugFirestoreOverride = null;
    PosPagamentoService.debugBuscarParticipacaoOverride = null;
  });

  group('gate puro — NO_ACTIVE_CAMPAIGN_MEANS_NO_RAFFLE', () {
    test('sem campanha → nenhuma', () {
      expect(_avaliar([]).status, CampanhaGateStatus.nenhuma);
    });

    test('uma campanha válida → ativa', () {
      final r = _avaliar([_camp()]);
      expect(r.status, CampanhaGateStatus.ativa);
      expect(r.campanhaId, 'c0');
    });

    for (final s in ['finalizada', 'sorteada', 'pausada', 'cancelada', 'encerrada', 'fechada', 'closed']) {
      test('status $s (mesmo com ativa=true) → nenhuma', () {
        expect(_avaliar([_camp(status: s)]).status, CampanhaGateStatus.nenhuma);
      });
    }

    test('ativa=false com status aberta (fail-open antigo) → nenhuma', () {
      expect(_avaliar([_camp(ativa: false)]).status, CampanhaGateStatus.nenhuma);
    });

    test('expirada → nenhuma', () {
      expect(
        _avaliar([_camp(inicio: const Duration(days: -5), fim: const Duration(days: -1))]).status,
        CampanhaGateStatus.nenhuma,
      );
    });

    test('futura → nenhuma', () {
      expect(
        _avaliar([_camp(inicio: const Duration(days: 1), fim: const Duration(days: 5))]).status,
        CampanhaGateStatus.nenhuma,
      );
    });

    test('sem datas (null antes valia "sem limite") → nenhuma', () {
      expect(_avaliar([_camp(semDatas: true)]).status, CampanhaGateStatus.nenhuma);
    });

    test('excluída → nenhuma', () {
      expect(_avaliar([_camp(extra: {'excluida': true})]).status, CampanhaGateStatus.nenhuma);
    });

    test('lojaId de outra loja no doc → nenhuma (CAMPAIGN_STORE_ISOLATION)', () {
      expect(_avaliar([_camp(lojaId: _outraLoja)]).status, CampanhaGateStatus.nenhuma);
    });

    test('duas válidas → ambígua (sem sorteio)', () {
      final r = _avaliar([_camp(), _camp()]);
      expect(r.status, CampanhaGateStatus.ambigua);
      expect(r.permiteSorteio, isFalse);
    });

    test('falha de consulta → falhaConsulta (CAMPAIGN_LOOKUP_FAILURE)', () async {
      CampanhaSorteioGate.debugCampanhasLoader = (_) async => throw Exception('unavailable');
      final r = await CampanhaSorteioGate.resolver(lojaId: _loja, agora: DateTime.now());
      expect(r.status, CampanhaGateStatus.falhaConsulta);
      expect(r.permiteSorteio, isFalse);
    });
  });

  group('PosPagamento — EMAIL_REQUIRES_PERSISTED_VALID_PARTICIPATION', () {
    test('SALE_WITHOUT_CAMPAIGN: sem campanha → sem número, sem e-mail de sorteio', () async {
      final r = await _resolverPos('601');
      expect(r.numero, isNull);
      expect(r.incluirNaNotificacao, isFalse);
      final numeros = await fs.collection('lojas').doc(_loja).collection('numerosSorte').get();
      expect(numeros.docs, isEmpty);
    });

    test('campanha encerrada → sem número', () async {
      await _seed(fs, {'enc': _camp(status: 'finalizada')});
      final r = await _resolverPos('602');
      expect(r.numero, isNull);
      expect(await _participantes(fs, 'enc'), 0);
    });

    test('campanha expirada / futura → sem número', () async {
      await _seed(fs, {
        'exp': _camp(inicio: const Duration(days: -9), fim: const Duration(days: -2)),
        'fut': _camp(inicio: const Duration(days: 2), fim: const Duration(days: 9)),
      });
      final r = await _resolverPos('603');
      expect(r.numero, isNull);
      expect(await _participantes(fs, 'exp'), 0);
      expect(await _participantes(fs, 'fut'), 0);
    });

    test('falha na consulta de campanhas → sem número', () async {
      await _seed(fs, {'ok': _camp()});
      CampanhaSorteioGate.debugCampanhasLoader = (_) async => throw Exception('x');
      final r = await _resolverPos('604');
      expect(r.numero, isNull);
      expect(r.incluirNaNotificacao, isFalse);
    });

    test('campanha válida só em OUTRA loja → sem número nesta loja', () async {
      await _seed(fs, {'ok': _camp()}, loja: _outraLoja);
      final r = await _resolverPos('605');
      expect(r.numero, isNull);
      expect(await _participantes(fs, 'ok', loja: _outraLoja), 0);
    });

    test('abaixo do valor mínimo → sem número', () async {
      await _seed(fs, {'ok': _camp(valorMinimo: 200)});
      final r = await _resolverPos('606', valor: 50);
      expect(r.numero, isNull);
      expect(await _participantes(fs, 'ok'), 0);
    });

    test('VALID_CAMPAIGN_FLOW: 1 campanha válida → participação persistida + e-mail com número', () async {
      await _seed(fs, {'ok': _camp()});
      final r = await _resolverPos('607');
      expect(r.numero, matches(RegExp(r'^\d{5}$')));
      expect(r.incluirNaNotificacao, isTrue);
      expect(r.campanhaId, 'ok');
      final doc = await fs
          .collection('lojas')
          .doc(_loja)
          .collection('campanhas_sorteio')
          .doc('ok')
          .collection('participantes')
          .doc(CampanhaSorteioGate.participacaoDocId('607'))
          .get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['numeroSorte'], r.numero);
      expect(doc.data()?['campanhaId'], 'ok');
      expect(doc.data()?['lojaId'], _loja);
      expect(doc.data()?['vendaId'], '607');
      expect(doc.data()?['status'], 'valido');
    });

    test('RAFFLE_PARTICIPATION/EMAIL_IDEMPOTENT: retry não duplica nem reenvia número', () async {
      await _seed(fs, {'ok': _camp()});
      final r1 = await _resolverPos('608');
      final r2 = await _resolverPos('608');
      expect(r2.numero, r1.numero);
      expect(r1.incluirNaNotificacao, isTrue);
      expect(r2.incluirNaNotificacao, isFalse);
      expect(await _participantes(fs, 'ok'), 1);
    });

    test('duas campanhas válidas → ambígua → sem número', () async {
      await _seed(fs, {'a': _camp(), 'b': _camp()});
      final r = await _resolverPos('609');
      expect(r.numero, isNull);
      expect(await _participantes(fs, 'a'), 0);
      expect(await _participantes(fs, 'b'), 0);
    });

    test('participação canônica cancelada não é reutilizada', () async {
      PosPagamentoService.debugBuscarParticipacaoOverride =
          ({required lojaId, required vendaId}) async => Participacao(
                id: 'p',
                campanhaId: 'x',
                numero: '12345',
                vendaId: vendaId,
                nomeCliente: 'C',
                totalVenda: 10,
                origem: 'manual',
                criadoEm: DateTime(2026),
                status: 'cancelado',
              );
      final r = await _resolverPos('610');
      expect(r.numero, isNull);
    });
  });

  group('relógio do cliente não ativa campanha', () {
    test('janela fora do horário do servidor → participação invalidada, sem número', () async {
      await _seed(fs, {
        'old': _camp(inicio: const Duration(days: -3), fim: const Duration(days: -1)),
      });
      final r = await CampanhaSorteioGate.registrarParticipacaoValidada(
        lojaId: _loja,
        vendaId: '611',
        valorCompra: 100,
        dadosParticipante: const {},
        agora: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(r, isNull);
      final doc = await fs
          .collection('lojas')
          .doc(_loja)
          .collection('campanhas_sorteio')
          .doc('old')
          .collection('participantes')
          .doc(CampanhaSorteioGate.participacaoDocId('611'))
          .get();
      expect(doc.data()?['status'], 'invalida');
    });
  });

  group('CampaignEngine (venda manual) usa o mesmo gate', () {
    test('sem campanha → semCampanha, nenhuma participação', () async {
      final r = await CampaignEngineService.onVendaConcluida(
        lojaId: _loja,
        vendaId: '700',
        clienteNome: 'C',
        valorTotal: 100,
      );
      expect(r.sucesso, isFalse);
      expect(r.numero, isNull);
    });

    test('ativa=false + status aberta (fail-open antigo) → sem participação', () async {
      await _seed(fs, {'x': _camp(ativa: false)});
      final r = await CampaignEngineService.onVendaConcluida(
        lojaId: _loja,
        vendaId: '701',
        clienteNome: 'C',
        valorTotal: 100,
      );
      expect(r.sucesso, isFalse);
      expect(await _participantes(fs, 'x'), 0);
    });

    test('campanha válida → participação única por venda', () async {
      await _seed(fs, {'ok': _camp()});
      final r1 = await CampaignEngineService.onVendaConcluida(
        lojaId: _loja,
        vendaId: '702',
        clienteNome: 'C',
        valorTotal: 100,
      );
      final r2 = await CampaignEngineService.onVendaConcluida(
        lojaId: _loja,
        vendaId: '702',
        clienteNome: 'C',
        valorTotal: 100,
      );
      expect(r1.sucesso, isTrue);
      expect(r1.numero, matches(RegExp(r'^\d{5}$')));
      expect(r2.sucesso, isFalse);
      expect(await _participantes(fs, 'ok'), 1);
    });
  });

  group('UI / notificação', () {
    test('e-mail sem sorteio não fala em concorrer nem número', () {
      final html = PosPagamentoService.montarEmailHtmlNotificacaoCliente(
        nome: 'C',
        lojaNome: 'Loja',
        numeroSorte: '',
        valorTotal: 10,
        incluirNumeroSorte: false,
      );
      expect(html, isNot(contains('Número da Sorte')));
      expect(html, isNot(contains('concorrendo')));
      expect(html, contains('Pedido confirmado'));
    });

    test('pré-pedidos só anuncia número da sorte quando foi enviado', () {
      final src = File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      expect(src, contains('PosPagamentoService.ultimaNotificacaoComNumeroSorte'));
    });
  });
}
