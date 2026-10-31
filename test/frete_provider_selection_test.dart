import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/frete_service.dart';
import 'package:master_palm/services/shipping_provider_selection.dart';

class _Chamadas {
  final List<String> provedores = [];
}

FreteCotadores _cotadores(
  _Chamadas chamadas, {
  bool meFalha = false,
  bool sfFalha = false,
  bool meVazio = false,
}) {
  FreteCotador ok(String nome, List<Map<String, dynamic>> Function() opcoes,
      {bool falha = false}) {
    return (pedido) async {
      chamadas.provedores.add(nome);
      if (falha) throw Exception('HttpsError failed-precondition');
      return opcoes();
    };
  }

  return FreteCotadores(
    melhorEnvio: ok(
      ShippingProviderSelection.melhorEnvio,
      () => meVazio
          ? []
          : [
              {'nome': 'SEDEX', 'valor': 30.0, 'empresa': 'Correios', 'service_id': 2, 'shipping_quote_id': 'a.0'},
              {'nome': 'PAC', 'valor': 20.0, 'empresa': 'Correios', 'service_id': 1, 'shipping_quote_id': 'a.1'},
            ],
      falha: meFalha,
    ),
    superFrete: ok(
      ShippingProviderSelection.superFrete,
      () => [
        {'nome': 'Mini Envios', 'valor': 12.0, 'empresa': 'Correios', 'plataforma': 'superfrete', 'servico_id': 17, 'shipping_quote_id': 'b.0'},
      ],
      falha: sfFalha,
    ),
    frenet: ok(ShippingProviderSelection.frenet, () => [{'nome': 'Frenet', 'valor': 9.0}]),
    correios: ok(ShippingProviderSelection.correios, () => [{'nome': 'PAC', 'valor': 8.0}]),
  );
}

Map<String, dynamic> _config({
  required String? provider,
  bool meConfigured = true,
  bool sfConfigured = true,
  List<Map<String, dynamic>> manual = const [],
  Map<String, dynamic>? integrations,
}) {
  return {
    if (provider != null) 'provider': provider,
    'cepOrigem': '35350000',
    'manualFretes': manual,
    'integrations': integrations ??
        {
          'melhor_envio': {'configured': meConfigured, 'enabled': true, 'sandbox': false},
          'superfrete': {'configured': sfConfigured, 'enabled': true, 'sandbox': false},
        },
  };
}

Future<FreteCalculoResultado> _calcular(Map<String, dynamic> config, FreteCotadores cotadores) {
  return FreteService.calcularComConfig(
    config: config,
    lojaId: 'loja-a',
    cep: '20040020',
    peso: 500,
    valorDeclarado: 150,
    itensCotacao: const [
      {'productId': 'p1', 'quantidade': 1},
    ],
    cotadores: cotadores,
  );
}

Set<String?> _plataformas(FreteCalculoResultado r) =>
    r.opcoes.map((o) => o['plataforma'] as String?).toSet();

void main() {
  const manuais = [
    {'nome': 'Retirada', 'valor': 0, 'tipo': 'retirada'},
    {'nome': 'Combinar com vendedor', 'valor': 0, 'tipo': 'combinar'},
  ];

  group('catálogo respeita o provedor selecionado', () {
    test('ME selecionado + ME ok + SF configurado: só ME é chamado', () async {
      final c = _Chamadas();
      final r = await _calcular(_config(provider: 'melhor_envio'), _cotadores(c));
      expect(c.provedores, ['melhor_envio']);
      expect(r.provider, 'melhor_envio');
      expect(r.erroProvedor, isNull);
      expect(_plataformas(r), {'melhor_envio'});
      expect(r.opcoes.map((o) => o['shipping_quote_id']), containsAll(['a.0', 'a.1']));
    });

    test('ME selecionado + ME falha: não chama SF, erro seguro, só manuais', () async {
      final c = _Chamadas();
      final r = await _calcular(
        _config(provider: 'melhor_envio', manual: manuais),
        _cotadores(c, meFalha: true),
      );
      expect(c.provedores, ['melhor_envio']);
      expect(r.erroProvedor, FreteService.mensagemFalhaProvedor);
      expect(_plataformas(r), {'manual'});
      expect(r.opcoes.map((o) => o['nome']), containsAll(['Retirada', 'Combinar com vendedor']));
      expect(r.opcoes.any((o) => o['shipping_quote_id'] != null), isFalse);
    });

    test('ME selecionado + ME sem opções: erro seguro, nada de SF', () async {
      final c = _Chamadas();
      final r = await _calcular(_config(provider: 'melhor_envio'), _cotadores(c, meVazio: true));
      expect(c.provedores, ['melhor_envio']);
      expect(r.erroProvedor, FreteService.mensagemFalhaProvedor);
      expect(_plataformas(r), {'manual'}, reason: 'fallback padrão é Retirada manual');
    });

    test('SF selecionado + SF ok + ME configurado: só SF é chamado', () async {
      final c = _Chamadas();
      final r = await _calcular(_config(provider: 'superfrete'), _cotadores(c));
      expect(c.provedores, ['superfrete']);
      expect(r.erroProvedor, isNull);
      expect(_plataformas(r), {'superfrete'});
    });

    test('SF selecionado + SF falha: não chama ME, erro seguro', () async {
      final c = _Chamadas();
      final r = await _calcular(
        _config(provider: 'superfrete', manual: manuais),
        _cotadores(c, sfFalha: true),
      );
      expect(c.provedores, ['superfrete']);
      expect(r.erroProvedor, FreteService.mensagemFalhaProvedor);
      expect(_plataformas(r), {'manual'});
    });

    test('só um configurado: selecionado sem integração não chama nenhum provedor', () async {
      final c = _Chamadas();
      final r = await _calcular(
        _config(provider: 'superfrete', sfConfigured: false, manual: manuais),
        _cotadores(c),
      );
      expect(c.provedores, isEmpty);
      expect(r.erroProvedor, isNull);
      expect(_plataformas(r), {'manual'});
    });

    test('manual selecionado: nenhum provedor, só fretes manuais', () async {
      final c = _Chamadas();
      final r = await _calcular(_config(provider: 'manual', manual: manuais), _cotadores(c));
      expect(c.provedores, isEmpty);
      expect(r.erroProvedor, isNull);
      expect(r.opcoes.length, 2);
      expect(_plataformas(r), {'manual'});
    });

    test('ME ok + manuais: manuais continuam como manual (não se passam por cotação)', () async {
      final c = _Chamadas();
      final r = await _calcular(_config(provider: 'melhor_envio', manual: manuais), _cotadores(c));
      expect(c.provedores, ['melhor_envio']);
      final porPlataforma = <String, int>{};
      for (final o in r.opcoes) {
        porPlataforma.update(o['plataforma'] as String, (v) => v + 1, ifAbsent: () => 1);
      }
      expect(porPlataforma, {'melhor_envio': 2, 'manual': 2});
    });

    test('doc sem provider com as duas integrações: não agrega (só manuais)', () async {
      final c = _Chamadas();
      final r = await _calcular(_config(provider: null, manual: manuais), _cotadores(c));
      expect(c.provedores, isEmpty);
      expect(r.provider, 'manual');
    });

    test('doc sem provider com só ME ativo: infere ME', () async {
      final c = _Chamadas();
      await _calcular(_config(provider: null, sfConfigured: false), _cotadores(c));
      expect(c.provedores, ['melhor_envio']);
    });
  });

  group('save/publish do admin: provedor selecionado é a autoridade', () {
    Map<String, dynamic> publicado(String provider) => {
          'provider': provider,
          'manualFretes': manuais,
          'integrations': ShippingProviderSelection.integrationsForSave(
            provider: provider,
            melhorEnvioConfigured: true,
            melhorEnvioSandbox: false,
            superFreteConfigured: true,
            superFreteSandbox: false,
          ),
        };

    test('selecionar ME: ME enabled, SF configured preservado e disabled', () {
      final i = publicado('melhor_envio')['integrations'] as Map<String, dynamic>;
      expect(i['melhor_envio'], {'configured': true, 'enabled': true, 'sandbox': false});
      expect(i['superfrete'], {'configured': true, 'enabled': false, 'sandbox': false});
    });

    test('selecionar SF: SF enabled, ME configured preservado e disabled', () {
      final i = publicado('superfrete')['integrations'] as Map<String, dynamic>;
      expect(i['superfrete'], {'configured': true, 'enabled': true, 'sandbox': false});
      expect(i['melhor_envio'], {'configured': true, 'enabled': false, 'sandbox': false});
    });

    test('admin ME → publicado → catálogo chama só ME', () async {
      final c = _Chamadas();
      final r = await _calcular(publicado('melhor_envio'), _cotadores(c));
      expect(c.provedores, ['melhor_envio']);
      expect(r.provider, 'melhor_envio');
    });

    test('admin SF → publicado → catálogo chama só SF', () async {
      final c = _Chamadas();
      final r = await _calcular(publicado('superfrete'), _cotadores(c));
      expect(c.provedores, ['superfrete']);
      expect(r.provider, 'superfrete');
    });

    test('telas de save/publish não gravam enabled fixo', () {
      final fretes = File('lib/screens/fretes_cupons_screen.dart').readAsStringSync();
      expect(fretes, contains('ShippingProviderSelection.integrationsForSave('));
      final integ = fretes.split("'integrations':")[1].split("'freteMelhorEnvioModoExibicao'")[0];
      expect(integ.contains("'enabled': true"), isFalse);

      final loja = File('lib/screens/loja_config_screen.dart').readAsStringSync();
      final pub = loja.split('// 2.1) Publica config/fretes')[1].split("'correios':")[0];
      expect(pub.contains("'enabled': true"), isFalse);
      expect(pub, contains("'enabled': provider == ShippingProviderSelection.superFrete"));
      expect(pub, contains("'enabled': provider == ShippingProviderSelection.melhorEnvio"));
    });
  });

  test('FreteService não tem fallback cruzado nem agregação', () {
    final src = File('lib/services/frete_service.dart').readAsStringSync();
    final calc = src.split('static Future<FreteCalculoResultado> calcularComConfig(')[1]
        .split('static bool _provedorConfigurado')[0];
    expect(calc, contains('cotadores.para(provider)'));
    expect(calc.contains('_isSuperFreteConfigured(config)'), isFalse);
    expect(calc.contains('_isMelhorEnvioConfigured(config)'), isFalse);
    final me = src.split('static Future<List<Map<String, dynamic>>> _calcularMelhorEnvio(')[1]
        .split('static List<Map<String, dynamic>> _parsearOpcoesFrenet')[0];
    expect(me.contains('_calcularManual'), isFalse);
  });
}
