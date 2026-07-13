// M3.7-HOMOLOG-FINAL-R2 — H12 produto trocado (ITEMID)

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_cart_item_snapshot.dart';
import 'package:master_palm/services/catalog_pre_pedido_compute.dart';

Map<String, dynamic> _produtoGota() => {
      'id': 'gota-doc',
      'produtosId': 'legacy-shared',
      'slug': 'anel-gota-paraiba',
      'nome': 'Anel Gota Paraíba',
      'preco': 150.0,
    };

Map<String, dynamic> _produtoTurmalina() => {
      'id': 'turmalina-doc',
      'produtosId': 'legacy-shared',
      'slug': 'anel-color-turmalina-regulavel',
      'nome': 'Anel Color Turmalina Regulável',
      'preco': 89.0,
    };

Map<String, dynamic> _cartLineGota() => {
      'id': 'gota-doc',
      'produtosId': 'gota-doc',
      'nome': 'Anel Gota Paraíba',
      'preco': 150.0,
      'quantidade': 1,
      'slug': 'anel-gota-paraiba',
    };

List<Map<String, dynamic>> _frozenGotaLines() {
  final line = _cartLineGota();
  freezeCatalogCartLineSnapshotOnAdd(line);
  return [line];
}

void main() {
  group('ITEMID — identidade imutável do item', () {
    test('ITEMID-1 adicionar A ao carrinho mantém productId A', () {
      final line = _cartLineGota();
      freezeCatalogCartLineSnapshotOnAdd(line);
      expect(line['productId'], 'gota-doc');
      expect(line['nomeSnapshot'], 'Anel Gota Paraíba');
      expect(line['schemaVersion'], catalogCartItemSchemaVersion);
    });

    test('ITEMID-2 roleta/enrich não troca item A por B', () {
      final line = _cartLineGota();
      freezeCatalogCartLineSnapshotOnAdd(line);
      final enriched = enrichCatalogCartLineSnapshot(
        line: line,
        catalogProducts: [_produtoTurmalina(), _produtoGota()],
      );
      expect(enriched['productId'], 'gota-doc');
      expect(enriched['nomeSnapshot'], 'Anel Gota Paraíba');
    });

    test('ITEMID-3 checkout mantém item A', () {
      final line = _cartLineGota();
      freezeCatalogCartLineSnapshotOnAdd(line);
      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: [line],
        catalogProducts: [_produtoTurmalina(), _produtoGota()],
      );
      expect(checkout.single['nomeSnapshot'], 'Anel Gota Paraíba');
      expect(checkout.single['productId'], 'gota-doc');
    });

    test('ITEMID-4 criarPrePedido grava A', () {
      final line = _cartLineGota();
      freezeCatalogCartLineSnapshotOnAdd(line);
      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: [line],
        catalogProducts: [_produtoTurmalina(), _produtoGota()],
      );
      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: checkout,
        entrega: {'valor': 0.0, 'freteGratis': true},
        pagamento: 'PIX',
      );
      expect(snap.itensList.single['productId'], 'gota-doc');
      expect(snap.itensList.single['nomeSnapshot'], 'Anel Gota Paraíba');
      expect(snap.itensList.single['schemaVersion'], catalogCartItemSchemaVersion);
    });

    test('ITEMID-5 WhatsApp usa A', () {
      final item = {
        'nomeSnapshot': 'Anel Gota Paraíba',
        'nome': 'Anel Color Turmalina Regulável',
      };
      expect(catalogPedidoItemDisplayName(item), 'Anel Gota Paraíba');
    });

    test('ITEMID-6 admin exibe A via snapshot', () {
      final stored = computeCatalogPrePedidoMoneySnapshot(
        items: prepareCatalogCheckoutCartItems(
          cartLines: _frozenGotaLines(),
          catalogProducts: [_produtoTurmalina(), _produtoGota()],
        ),
        entrega: {'valor': 0.0, 'freteGratis': true},
        pagamento: 'CARTAO',
      ).itensList.single;
      expect(catalogPedidoItemDisplayName(stored), 'Anel Gota Paraíba');
    });

    test('ITEMID-7 confirmação mantém productId A', () {
      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: prepareCatalogCheckoutCartItems(
          cartLines: _frozenGotaLines(),
          catalogProducts: [_produtoTurmalina(), _produtoGota()],
        ),
        entrega: {'valor': 10.0, 'freteGratis': false},
        pagamento: 'CARTAO',
      );
      expect(snap.itensList.single['id'], 'gota-doc');
      expect(snap.itensList.single['firestoreDocId'], 'gota-doc');
    });

    test('ITEMID-8 histórico mostra A', () {
      final nome = catalogPedidoItemDisplayName({
        'nomeSnapshot': 'Anel Gota Paraíba',
      });
      expect(nome, 'Anel Gota Paraíba');
    });

    test('ITEMID-9 cache/lista reordenada não troca A', () {
      final line = _cartLineGota();
      freezeCatalogCartLineSnapshotOnAdd(line);
      final checkout = prepareCatalogCheckoutCartItems(
        cartLines: [line],
        catalogProducts: [_produtoGota(), _produtoTurmalina()],
      );
      expect(checkout.single['nomeSnapshot'], 'Anel Gota Paraíba');
    });

    test('ITEMID-10 produto B não aparece em nenhum estágio', () {
      final snap = computeCatalogPrePedidoMoneySnapshot(
        items: prepareCatalogCheckoutCartItems(
          cartLines: _frozenGotaLines(),
          catalogProducts: [_produtoTurmalina(), _produtoGota()],
        ),
        entrega: {'valor': 0.0, 'freteGratis': true},
        pagamento: 'PIX',
      );
      for (final item in snap.itensList) {
        expect(item['productId'], isNot('turmalina-doc'));
        expect(item['nomeSnapshot'], isNot(contains('Turmalina')));
      }
    });

    test('ITEMID-RED colisão produtosId — lookup legado errado, snapshot preserva A', () {
      final catalog = [_produtoTurmalina(), _produtoGota()];

      final loose =
          CatalogEstoqueHelper.findProductInList(catalog, 'legacy-shared');
      expect(loose?['nome'], 'Anel Color Turmalina Regulável');

      final strict =
          findCatalogProductForCartLineStrict(catalog, 'legacy-shared');
      expect(strict, isNull);

      final line = {
        'id': 'legacy-shared',
        'produtosId': 'legacy-shared',
        'nome': 'Anel Gota Paraíba',
        'preco': 150.0,
        'quantidade': 1,
      };
      freezeCatalogCartLineSnapshotOnAdd(line);

      final enriched = enrichCatalogCartLineSnapshot(
        line: line,
        catalogProducts: catalog,
      );
      expect(enriched['nomeSnapshot'], 'Anel Gota Paraíba');
      expect(enriched['nome'], 'Anel Gota Paraíba');
      expect(enriched['productId'], 'legacy-shared');
    });

    test('ITEMID-RED colisão id duplicado no catálogo — enrich preserva snapshot', () {
      final catalog = [
        {
          'id': 'gota-doc',
          'produtosId': 'p-turmalina',
          'slug': 'anel-color-turmalina-regulavel',
          'nome': 'Anel Color Turmalina Regulável',
          'preco': 89.0,
        },
        {
          'id': 'gota-doc',
          'produtosId': 'p-gota',
          'slug': 'anel-gota-paraiba',
          'nome': 'Anel Gota Paraíba',
          'preco': 150.0,
        },
      ];

      final loose =
          CatalogEstoqueHelper.findProductInList(catalog, 'gota-doc');
      expect(loose?['nome'], 'Anel Color Turmalina Regulável');

      final line = {
        'id': 'gota-doc',
        'nome': 'Anel Gota Paraíba',
        'preco': 150.0,
        'quantidade': 1,
      };
      freezeCatalogCartLineSnapshotOnAdd(line);
      final enriched = enrichCatalogCartLineSnapshot(
        line: line,
        catalogProducts: catalog,
      );
      expect(enriched['nomeSnapshot'], 'Anel Gota Paraíba');
      expect(enriched['productId'], 'gota-doc');
    });
  });
}
