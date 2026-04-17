// Smoke/regressão leve: catálogo público (URL, estoque, strings de pré-pedido).
// Não cobre UI nem Cloud Functions; não altera lógica de pagamento MP.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/screens/public_catalog/catalog_url_query_codec.dart';
import 'package:master_palm/services/pre_pedido_helpers.dart';

void main() {
  group('A. Deep link / URL sync (catalog_url_query_codec)', () {
    test('ordenacao: aliases estáveis (menor_preco → preco_asc)', () {
      expect(catalogOrdQueryToInternal('menor_preco'), 'preco_asc');
      expect(catalogOrdQueryToInternal('MAIOR_PRECO'), 'preco_desc');
      expect(catalogOrdInternalToQuery('preco_asc'), 'menor_preco');
      expect(catalogOrdInternalIsValid('nome'), isTrue);
      expect(catalogOrdInternalIsValid('invalid'), isFalse);
    });

    test('prod (deep link produto): trim, vazio e limite', () {
      expect(catalogSanitizeProdQuery('  abc  '), 'abc');
      expect(catalogSanitizeProdQuery(''), isNull);
      expect(catalogSanitizeProdQuery('x' * 200), isNull);
    });

    test('page: grid numérico vs rota nomeada dicas', () {
      final a = catalogInterpretPageQueryParam('3');
      expect(a.catalogPage1Based, 3);
      expect(a.namedInitialPage, isNull);
      final b = catalogInterpretPageQueryParam('dicas');
      expect(b.catalogPage1Based, isNull);
      expect(b.namedInitialPage, 'dicas');
      final c = catalogInterpretPageQueryParam('lixo');
      expect(c.catalogPage1Based, isNull);
      expect(c.namedInitialPage, isNull);
    });

    test('busca q: sanitize', () {
      expect(catalogSanitizeSearchQuery('  x  '), 'x');
      expect(catalogSanitizeSearchQuery('   '), isNull);
    });

    test('paginação: format omite página 1', () {
      expect(
        catalogFormatPaginationPageQuery(zeroBasedPage: 0, totalPaginas: 5),
        isNull,
      );
      expect(
        catalogFormatPaginationPageQuery(zeroBasedPage: 2, totalPaginas: 5),
        '3',
      );
    });
  });

  group('B/C. Carrinho + estoque (CatalogEstoqueHelper)', () {
    test('parseCartItemQuantidade: null → 1', () {
      expect(CatalogEstoqueHelper.parseCartItemQuantidade(null), 1);
      expect(CatalogEstoqueHelper.parseCartItemQuantidade('3'), 3);
    });

    test('add com estoque ok: produto simples só quantidade', () {
      final p = <String, dynamic>{'id': 'p1', 'quantidade': 12};
      final avail = CatalogEstoqueHelper.estoqueDisponivelVariacao(p, '', '');
      expect(avail, 12);
    });

    test('bloqueio lógico: estoque insuficiente = UI compara qty > avail', () {
      final p = <String, dynamic>{'quantidade': 3};
      final avail = CatalogEstoqueHelper.estoqueDisponivelVariacao(p, '', '');
      expect(avail, 3);
      const requested = 5;
      expect(requested > avail, isTrue);
    });

    test('update qty: mesma função de disponível para rechecagem', () {
      final p = <String, dynamic>{'estoque': 10, 'quantidade': 10};
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, '', ''), 10);
    });

    test('findProductInList: id, depois slug', () {
      final list = [
        {'id': 'a', 'nome': 'A'},
        {'id': 'b', 'slug': 'slug-b', 'nome': 'B'},
      ];
      expect(CatalogEstoqueHelper.findProductInList(list, 'a')?['nome'], 'A');
      expect(CatalogEstoqueHelper.findProductInList(list, 'slug-b')?['nome'], 'B');
      expect(CatalogEstoqueHelper.findProductInList(list, 'missing'), isNull);
    });

    test('cartLineIdentity: estável para merge', () {
      final id = CatalogEstoqueHelper.cartLineIdentity({
        'id': '1',
        'tamanho': 'M',
        'cor': 'Azul',
        'quantidade': 2,
      });
      expect(id.contains('1'), isTrue);
      expect(id.contains('m'), isTrue);
      expect(id.contains('azul'), isTrue);
    });

    test('produto não publicado: catalogoWebDocPublicado', () {
      expect(CatalogEstoqueHelper.catalogoWebDocPublicado({}), isTrue);
      expect(
        CatalogEstoqueHelper.catalogoWebDocPublicado({'publicadoNoCatalogo': false}),
        isFalse,
      );
    });
  });

  group('C/E. Pré-pedido — helpers de texto (sem Firestore)', () {
    test('status pagamento: MP/PIX pendente; manual aprovado', () {
      expect(determinarStatusPagamento('mercadopago'), 'pendente');
      expect(determinarStatusPagamento('PIX'), 'pendente');
      expect(determinarStatusPagamento('dinheiro'), 'aprovado');
    });

    test('formatação valor BR', () {
      expect(formatarValor(10.5), '10,50');
    });
  });

}
