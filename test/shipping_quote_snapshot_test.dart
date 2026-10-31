import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/shipping_quote_snapshot.dart';

void main() {
  const quoteId = 'abcdef0123456789abcdef0123456789.1';

  group('itens da cotação', () {
    test('um item por linha com productId canônico e quantidade', () {
      final itens = buildShippingQuoteItems([
        {'productId': 'p1', 'quantidade': 2, 'peso': 999, 'preco': 1},
        {'id': 'p2', 'quantidade': 1.0},
        {'nome': 'sem id'},
      ]);
      expect(itens, [
        {'productId': 'p1', 'quantidade': 2},
        {'productId': 'p2', 'quantidade': 1},
      ]);
      expect(itens.first.containsKey('peso'), isFalse,
          reason: 'peso/preço não vão para a cotação');
    });

    test('assinatura agrega por produto e muda quando o carrinho muda', () {
      final a = shippingQuoteItemsSignature([
        {'productId': 'p2', 'quantidade': 1},
        {'productId': 'p1', 'quantidade': 1, 'tamanho': 'P'},
        {'productId': 'p1', 'quantidade': 1, 'tamanho': 'M'},
      ]);
      expect(a, 'p1:2|p2:1');
      expect(
        shippingQuoteItemsSignature([
          {'productId': 'p1', 'quantidade': 3},
          {'productId': 'p2', 'quantidade': 1},
        ]),
        isNot(a),
      );
    });
  });

  group('sanitizeShippingQuoteId', () {
    test('aceita só o formato emitido pelo servidor', () {
      expect(sanitizeShippingQuoteId(quoteId), quoteId);
      expect(sanitizeShippingQuoteId(' $quoteId '), quoteId);
      for (final bad in [
        null,
        '',
        'abc.1',
        '${quoteId}99',
        'ABCDEF0123456789ABCDEF0123456789.1',
        '../x',
        {'price': 1},
      ]) {
        expect(sanitizeShippingQuoteId(bad), isNull, reason: '$bad');
      }
    });
  });

  group('buildCatalogCheckoutEntrega', () {
    test('frete de provedor leva só o shippingQuoteId (sem pacote/preço cotado)', () {
      final entrega = buildCatalogCheckoutEntrega(
        freteSelecionado: {
          'nome': 'SEDEX',
          'valor': 15.0,
          'tipo': 'melhor_envio',
          'plataforma': 'melhor_envio',
          'service_id': 4,
          'shipping_quote_id': quoteId,
        },
        nome: 'SEDEX',
        valorFinal: 15.0,
        freteGratis: false,
      );
      expect(entrega['shippingQuoteId'], quoteId);
      expect(entrega['service_id'], 4);
      expect(entrega['plataforma'], 'melhor_envio');
      expect(entrega.containsKey('cotacao'), isFalse);
    });

    test('frete manual não leva shippingQuoteId; ID forjado é descartado', () {
      final manual = buildCatalogCheckoutEntrega(
        freteSelecionado: {
          'nome': 'Retirada',
          'tipo': 'retirada',
          'plataforma': 'manual',
          'shipping_quote_id': quoteId,
        },
        nome: 'Retirada',
        valorFinal: 0,
        freteGratis: true,
      );
      expect(manual.containsKey('shippingQuoteId'), isFalse);
      final forjado = buildCatalogCheckoutEntrega(
        freteSelecionado: {
          'plataforma': 'superfrete',
          'servico_id': 1,
          'shipping_quote_id': 'qualquer',
        },
        nome: 'PAC',
        valorFinal: 1,
        freteGratis: false,
      );
      expect(forjado.containsKey('shippingQuoteId'), isFalse);
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

    test('carrinho envia itens à cotação, guarda o ID e recota se o carrinho mudou', () {
      final src = File('lib/screens/public_catalog/widgets/carrinho_sheet_web.dart')
          .readAsStringSync();
      expect('buildCatalogCheckoutEntrega('.allMatches(src).length, 3);
      expect(src, contains('itensCotacao: buildShippingQuoteItems(widget.items)'));
      expect(src, contains("'shipping_quote_id': opcao['shipping_quote_id']"));
      expect(src, contains("'servico_id': opcao['servico_id']"));
      expect(
        'if (!await _cotacaoFreteAtualOuRecalcular()) return;'.allMatches(src).length,
        3,
      );
      expect(src.contains('_cotacaoPacote'), isFalse);
    });

    test('FreteService repassa itens e o ID nas duas plataformas', () {
      final src = File('lib/services/frete_service.dart').readAsStringSync();
      expect(src, contains("'items': itensCotacao"));
      expect(src, contains(RegExp(r'items: (p\.)?itensCotacao')));
      expect(
        "'shipping_quote_id': m['shippingQuoteId'].toString()".allMatches(src).length +
            "'shipping_quote_id': item['shippingQuoteId'].toString()"
                .allMatches(src)
                .length,
        2,
      );
    });

    test('pre_pedido_service grava só frete.shippingQuoteId sanitizado', () {
      final src =
          File('lib/services/pre_pedido_service.dart').readAsStringSync();
      expect(src, contains("sanitizeShippingQuoteId(entrega['shippingQuoteId'])"));
      expect(src, contains("'shippingQuoteId': shippingQuoteId"));
      expect(src.contains("'cotacao'"), isFalse);
    });
  });
}
