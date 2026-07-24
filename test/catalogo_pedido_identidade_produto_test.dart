// M2.3-R1 — regressão identidade catálogo → carrinho → pré-pedido → WhatsApp.
// Cenário real: preço do produto B com nome/variação do produto A.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';
import 'package:master_palm/services/pre_pedido_service.dart';

const _nomeA = 'Colar Coração Cravejado Rosa';
const _nomeB = 'Colar Ponto de Luz Gota 45cm';
const _precoB = 79.90;
const _pctPixB = 5.0; // 75,91
const _precoPixB = 75.91;
const _tamA = 'coracao-rosa';
const _tamB = 'gota-45cm';

Map<String, dynamic> _produtoA() => {
      'id': 'produto-a',
      'produtosId': 'produto-a',
      'slug': 'colar-coracao-cravejado-rosa',
      'nome': _nomeA,
      'preco': 120.0,
      'percentualDescontoPix': 0.0,
      'variacoes': {
        _tamA: {'sem-cor': 3},
      },
    };

Map<String, dynamic> _produtoB() => {
      'id': 'produto-b',
      'produtosId': 'produto-b',
      'slug': 'colar-ponto-luz-gota-45cm',
      'nome': _nomeB,
      'preco': _precoB,
      'percentualDescontoPix': _pctPixB,
      'variacoes': {
        _tamB: {'sem-cor': 5},
      },
    };

/// Simula item produzido por [CatalogProductDetailScreen._onCommitVariacao].
Map<String, dynamic> _linhaDetalhe({
  required Map<String, dynamic> produto,
  required String tamanho,
  String cor = 'sem-cor',
  double? precoOverride,
}) {
  final id = produto['id'] as String;
  final preco = precoOverride ?? (produto['preco'] as num).toDouble();
  return {
    'produtosId': id,
    'id': id,
    'nome': produto['nome'],
    'preco': preco,
    'percentualDescontoPix': produto['percentualDescontoPix'] ?? 0.0,
    'quantidade': 1,
    'tamanho': tamanho,
    'cor': cor,
    'slug': produto['slug'],
  };
}

void _assertItemCoerente(
  Map<String, dynamic> item, {
  required String produtoId,
  required String nome,
  required double precoPix,
  required String tamanho,
}) {
  expect(item['productId'] ?? item['id'], produtoId);
  expect(item['nomeSnapshot'] ?? item['nome'], nome);
  expect(item['tamanho'], tamanho);
  final pu = (item['precoUnitario'] as num?)?.toDouble() ??
      (item['precoUnitarioSnapshot'] as num?)?.toDouble() ??
      (item['preco'] as num?)?.toDouble();
  final pix = (item['precoPixSnapshot'] as num?)?.toDouble() ?? pu;
  expect(pix, closeTo(precoPix, 0.01));
  expect(
    catalogPedidoItemDisplayName(item),
    nome,
    reason: 'nome exibido deve coincidir com snapshot',
  );
}

void main() {
  final catalog = [_produtoA(), _produtoB()];

  group('INVARIANTE 1/4/5 — navegação A→B, adiciona só B', () {
    test('carrinho → checkout PIX → pré-pedido → WhatsApp usam produto-b', () {
      // 1–4: visualizar A, selecionar variação; visualizar B, selecionar variação.
      // 5: adicionar somente B (snapshot congelado no add).
      final linhaB = _linhaDetalhe(produto: _produtoB(), tamanho: _tamB);
      freezeCatalogCartLineSnapshotOnAdd(linhaB);
      final cart = [linhaB];

      _assertItemCoerente(
        cart.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        precoPix: _precoB,
        tamanho: _tamB,
      );

      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: cart,
        catalogProducts: catalog,
        pagamento: 'PIX',
      );
      _assertItemCoerente(
        checkout.single,
        produtoId: 'produto-b',
        nome: _nomeB,
        precoPix: _precoPixB,
        tamanho: _tamB,
      );

      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: checkout,
        entrega: {'valor': 0.0, 'freteGratis': true},
        pagamento: 'PIX',
      );
      final stored = snap.itensList.single;
      _assertItemCoerente(
        stored,
        produtoId: 'produto-b',
        nome: _nomeB,
        precoPix: _precoPixB,
        tamanho: _tamB,
      );

      final prePedido = <String, dynamic>{
        'id': 'pp-ident-r1',
        'itens': snap.itensList,
        'subtotal': snap.subtotal,
        'total': snap.total,
        'pagamento': 'PIX',
        'frete': {'nome': 'Retirada', 'valor': 0.0, 'gratis': true},
      };

      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: prePedido,
        lojaId: 'loja-ident-r1',
      );
      expect(msg, contains(_nomeB));
      expect(msg, isNot(contains(_nomeA)));
      expect(msg, contains('75,91'));
      expect(msg, isNot(contains('120,00')));
    });

    test('characterization_contaminated_line_is_frozen_and_propagated_downstream', () {
      // Este teste não reproduz a origem na UI.
      // Este teste caracteriza a propagação downstream de uma entrada já contaminada.
      final contaminada = _linhaDetalhe(
        produto: _produtoB(),
        tamanho: _tamA,
        precoOverride: _precoB,
      );
      contaminada['nome'] = _nomeA;
      freezeCatalogCartLineSnapshotOnAdd(contaminada);

      expect(contaminada['productId'] ?? contaminada['id'], 'produto-b');
      expect(contaminada['nomeSnapshot'], _nomeA);
      expect(contaminada['tamanho'], _tamA);
      expect(
        (contaminada['precoUnitarioSnapshot'] as num?)?.toDouble(),
        closeTo(_precoB, 0.01),
      );

      // Sem catálogo no enrich: snapshot contaminado propaga (não há lookup semântico).
      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: [contaminada],
        catalogProducts: const [],
        pagamento: 'PIX',
      );
      final itemCheckout = checkout.single;
      expect(itemCheckout['productId'], 'produto-b');
      expect(itemCheckout['nomeSnapshot'], _nomeA);
      expect(itemCheckout['tamanho'], _tamA);
      expect(
        (itemCheckout['precoPixSnapshot'] as num?)?.toDouble(),
        closeTo(_precoPixB, 0.01),
      );

      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: checkout,
        entrega: {'valor': 0.0, 'freteGratis': true},
        pagamento: 'PIX',
      );
      final stored = snap.itensList.single;
      expect(stored['productId'], 'produto-b');
      expect(stored['nomeSnapshot'], _nomeA);
      expect(stored['tamanho'], _tamA);

      final prePedido = <String, dynamic>{
        'id': 'pp-contam-r4',
        'itens': snap.itensList,
        'subtotal': snap.subtotal,
        'total': snap.total,
        'pagamento': 'PIX',
        'frete': {'nome': 'Retirada', 'valor': 0.0, 'gratis': true},
      };

      final msg = PrePedidoService.formatarParaWhatsApp(
        prePedido: prePedido,
        lojaId: 'loja-contam-r4',
      );
      expect(msg, contains(_nomeA));
      expect(msg, isNot(contains(_nomeB)));
      expect(msg, contains('75,91'));
      expect(
        catalogPedidoItemDisplayName(stored),
        _nomeA,
        reason: 'downstream não reconstrói produto sem catálogo',
      );
    });
  });

  group('INVARIANTE 1 — carrinho com A e B simultâneos', () {
    test('linhas distintas não trocam nome, preço ou variacaoId', () {
      final linhaA = _linhaDetalhe(produto: _produtoA(), tamanho: _tamA);
      final linhaB = _linhaDetalhe(produto: _produtoB(), tamanho: _tamB);
      freezeCatalogCartLineSnapshotOnAdd(linhaA);
      freezeCatalogCartLineSnapshotOnAdd(linhaB);

      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: [linhaA, linhaB],
        catalogProducts: catalog,
        pagamento: 'PIX',
      );
      expect(checkout.length, 2);

      final a = checkout.firstWhere((e) => e['productId'] == 'produto-a');
      final b = checkout.firstWhere((e) => e['productId'] == 'produto-b');

      _assertItemCoerente(
        a,
        produtoId: 'produto-a',
        nome: _nomeA,
        precoPix: 120.0,
        tamanho: _tamA,
      );
      _assertItemCoerente(
        b,
        produtoId: 'produto-b',
        nome: _nomeB,
        precoPix: _precoPixB,
        tamanho: _tamB,
      );

      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: checkout,
        entrega: {'valor': 0.0, 'freteGratis': true},
        pagamento: 'PIX',
      );
      expect(snap.itensList.length, 2);
      for (final it in snap.itensList) {
        final pid = it['productId'];
        if (pid == 'produto-a') {
          expect(it['nomeSnapshot'], _nomeA);
          expect(it['tamanho'], _tamA);
        } else if (pid == 'produto-b') {
          expect(it['nomeSnapshot'], _nomeB);
          expect(it['tamanho'], _tamB);
        } else {
          fail('produtoId inesperado: $pid');
        }
      }
    });
  });
}
