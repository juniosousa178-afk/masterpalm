import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/shipping_quote_snapshot.dart';

void main() {
  final pacote = buildShippingQuotePackage(
    pesoGramas: 450,
    alturaCm: 10,
    larguraCm: 15,
    comprimentoCm: 20,
  );

  group('buildShippingQuoteSnapshot', () {
    test('Melhor Envio: provider, serviço, transportadora, preço, prazo e pacote', () {
      final snap = buildShippingQuoteSnapshot(
        freteSelecionado: {
          'nome': 'SEDEX',
          'valor': 23.5,
          'prazo': '3 dias úteis',
          'prazo_dias': 3,
          'empresa': 'Correios',
          'plataforma': 'melhor_envio',
          'service_id': 2,
          'company_id': 1,
        },
        pacote: pacote,
      );
      expect(snap, isNotNull);
      expect(snap!['provider'], 'melhor_envio');
      expect(snap['serviceId'], 2);
      expect(snap['serviceName'], 'SEDEX');
      expect(snap['carrierName'], 'Correios');
      expect(snap['companyId'], 1);
      expect(snap['quotedPrice'], 23.5);
      expect(snap['quotedDeadlineDays'], 3);
      expect(snap['pacote'], {
        'pesoGramas': 450.0,
        'alturaCm': 10.0,
        'larguraCm': 15.0,
        'comprimentoCm': 20.0,
      });
    });

    test('SuperFrete usa servico_id', () {
      final snap = buildShippingQuoteSnapshot(
        freteSelecionado: {
          'nome': 'PAC',
          'valor': 18.0,
          'prazo': '7 dias úteis',
          'empresa': 'Correios',
          'plataforma': 'superfrete',
          'servico_id': 1,
        },
        pacote: pacote,
      );
      expect(snap!['provider'], 'superfrete');
      expect(snap['serviceId'], 1);
      expect(snap['quotedDeadlineDays'], 7);
    });

    test('frete manual / retirada não gera snapshot', () {
      for (final plataforma in ['manual', null, 'frenet', 'correios']) {
        expect(
          buildShippingQuoteSnapshot(
            freteSelecionado: {
              'nome': 'Retirada',
              'valor': 0.0,
              'tipo': 'retirada',
              if (plataforma != null) 'plataforma': plataforma,
            },
            pacote: pacote,
          ),
          isNull,
        );
      }
    });

    test('sem pacote ou sem serviço não gera snapshot', () {
      final frete = {
        'nome': 'SEDEX',
        'valor': 23.5,
        'plataforma': 'melhor_envio',
        'service_id': 2,
      };
      expect(buildShippingQuoteSnapshot(freteSelecionado: frete, pacote: null),
          isNull);
      expect(
        buildShippingQuoteSnapshot(
          freteSelecionado: {...frete}..remove('service_id'),
          pacote: pacote,
        ),
        isNull,
      );
    });
  });

  group('sanitizeShippingQuoteSnapshot', () {
    test('descarta chaves desconhecidas e valores inválidos', () {
      final clean = sanitizeShippingQuoteSnapshot({
        'provider': 'melhor_envio',
        'serviceId': '2',
        'quotedPrice': 20,
        'token': 'nao-deve-ficar',
        'pacote': {
          'pesoGramas': 300,
          'alturaCm': 2,
          'larguraCm': 11,
          'comprimentoCm': 16,
          'extra': true,
        },
      });
      expect(clean, isNotNull);
      expect(clean!.containsKey('token'), isFalse);
      expect((clean['pacote'] as Map).containsKey('extra'), isFalse);
      expect(clean['serviceId'], 2);
    });

    test('rejeita provider desconhecido, preço zero e pacote incompleto', () {
      final base = {
        'provider': 'melhor_envio',
        'serviceId': 2,
        'quotedPrice': 20,
        'pacote': {
          'pesoGramas': 300,
          'alturaCm': 2,
          'larguraCm': 11,
          'comprimentoCm': 16,
        },
      };
      expect(sanitizeShippingQuoteSnapshot({...base, 'provider': 'outro'}),
          isNull);
      expect(sanitizeShippingQuoteSnapshot({...base, 'quotedPrice': 0}),
          isNull);
      expect(
        sanitizeShippingQuoteSnapshot({
          ...base,
          'pacote': {'pesoGramas': 300},
        }),
        isNull,
      );
      expect(sanitizeShippingQuoteSnapshot(null), isNull);
    });
  });

  group('buildCatalogCheckoutEntrega', () {
    test('mantém campos atuais e inclui cotacao para provedor', () {
      final entrega = buildCatalogCheckoutEntrega(
        freteSelecionado: {
          'nome': 'PAC',
          'valor': 18.0,
          'tipo': 'superfrete',
          'plataforma': 'superfrete',
          'servico_id': 1,
          'empresa': 'Correios',
        },
        nome: 'PAC',
        valorFinal: 18.0,
        freteGratis: false,
        pacoteCotacao: pacote,
      );
      expect(entrega['servico_id'], 1);
      expect(entrega['plataforma'], 'superfrete');
      expect(entrega['valor'], 18.0);
      expect(entrega['cotacao'], isA<Map>());
    });

    test('retirada não leva cotacao', () {
      final entrega = buildCatalogCheckoutEntrega(
        freteSelecionado: {
          'nome': 'Retirada',
          'valor': 0.0,
          'tipo': 'retirada',
          'plataforma': 'manual',
        },
        nome: 'Retirada',
        valorFinal: 0,
        freteGratis: false,
        pacoteCotacao: pacote,
      );
      expect(entrega.containsKey('cotacao'), isFalse);
    });
  });

  group('fonte — seleção de frete não chama provedor', () {
    test('helper não faz IO nem conhece endpoints', () {
      final src =
          File('lib/services/shipping_quote_snapshot.dart').readAsStringSync();
      for (final forbidden in [
        'httpsCallable',
        'http.',
        'melhorenvio.com.br',
        'superfrete.com',
        'FirebaseFirestore',
      ]) {
        expect(src.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('carrinho usa o helper nos três checkouts e guarda servico_id', () {
      final src = File('lib/screens/public_catalog/widgets/carrinho_sheet_web.dart')
          .readAsStringSync();
      expect(
        'buildCatalogCheckoutEntrega('.allMatches(src).length,
        3,
      );
      expect(src, contains("'servico_id': opcao['servico_id']"));
      expect(src, contains('_cotacaoPacote = buildShippingQuotePackage('));
    });

    test('pre_pedido_service grava frete.cotacao sanitizado', () {
      final src =
          File('lib/services/pre_pedido_service.dart').readAsStringSync();
      expect(src, contains("sanitizeShippingQuoteSnapshot(entrega['cotacao'])"));
      expect(src, contains("'cotacao': cotacaoFrete"));
    });
  });
}
