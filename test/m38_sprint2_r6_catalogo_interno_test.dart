// M3.8 S2-R6 — catálogo interno (carrinho → Nova Venda) + hotfix vendedores.

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/catalogo_interno_cart.dart';
import 'package:master_palm/core/home_module_registry.dart';
import 'package:master_palm/core/app_module_definition.dart';

import 'package:master_palm/widgets/home_quick_actions_row.dart';

void main() {
  group('R6 — CatalogoInternoCartLogic', () {
    CatalogoInternoCartItem item({
      String id = 'p1',
      String nome = 'Anel',
      double preco = 10,
      int qtd = 1,
      String tam = '',
      String cor = '',
    }) =>
        CatalogoInternoCartItem(
          productId: id,
          nome: nome,
          preco: preco,
          quantidade: qtd,
          tamanho: tam,
          cor: cor,
        );

    test('R6-CART-1 addOrMerge soma quantidade na mesma linha', () {
      var cart = <CatalogoInternoCartItem>[];
      cart = CatalogoInternoCartLogic.addOrMerge(cart, item(qtd: 1));
      cart = CatalogoInternoCartLogic.addOrMerge(cart, item(qtd: 2));
      expect(cart, hasLength(1));
      expect(cart.first.quantidade, 3);
    });

    test('R6-CART-2 linhas diferentes por tamanho', () {
      var cart = <CatalogoInternoCartItem>[];
      cart = CatalogoInternoCartLogic.addOrMerge(cart, item(tam: 'M'));
      cart = CatalogoInternoCartLogic.addOrMerge(cart, item(tam: 'G'));
      expect(cart, hasLength(2));
    });

    test('R6-CART-3 setQuantity remove se < 1', () {
      var cart = [item(qtd: 2)];
      cart = CatalogoInternoCartLogic.setQuantity(cart, cart.first.lineKey, 0);
      expect(cart, isEmpty);
    });

    test('R6-CART-4 setQuantity altera', () {
      var cart = [item(qtd: 1)];
      cart = CatalogoInternoCartLogic.setQuantity(cart, cart.first.lineKey, 5);
      expect(cart.single.quantidade, 5);
    });

    test('R6-CART-5 remove', () {
      var cart = [item(id: 'a'), item(id: 'b')];
      cart = CatalogoInternoCartLogic.remove(cart, cart.first.lineKey);
      expect(cart.single.productId, 'b');
    });

    test('R6-CART-6 subtotal', () {
      final cart = [
        item(preco: 10, qtd: 2),
        item(id: 'p2', preco: 5, qtd: 3),
      ];
      expect(CatalogoInternoCartLogic.subtotal(cart), 35);
    });

    test('R6-CART-7 toNovaVendaItens shape', () {
      final maps = CatalogoInternoCartLogic.toNovaVendaItens([
        item(id: 'abc', nome: 'Pulseira', preco: 49.9, qtd: 2, tam: 'U'),
      ]);
      expect(maps.single['produto'], 'Pulseira');
      expect(maps.single['preco'], 49.9);
      expect(maps.single['quantidade'], 2);
      expect(maps.single['tamanho'], 'U');
      expect(maps.single['productId'], 'abc');
    });

    test('R6.1-CART-9 toNovaVendaItens descarta nome vazio (sem card fantasma)',
        () {
      final maps = CatalogoInternoCartLogic.toNovaVendaItens([
        item(id: 'x', nome: '   ', preco: 1),
        item(id: 'abc', nome: 'Pulseira', preco: 49.9, qtd: 1),
      ]);
      expect(maps, hasLength(1));
      expect(maps.first['produto'], 'Pulseira');
    });

    test('R6-CART-8 joinObservacoes', () {
      final a = item(nome: 'A');
      a.observacao = 'sem caixa';
      final text = CatalogoInternoCartLogic.joinObservacoes([
        a,
        item(id: 'x', nome: 'B'),
      ]);
      expect(text, contains('A: sem caixa'));
      expect(text, isNot(contains('B:')));
    });
  });

  group('R6 — registry comercial', () {
    test('R6-REG-1 catalogo_interno em vendas com chave vendas', () {
      final m = HomeModuleRegistry.byId('catalogo_interno')!;
      expect(m.category, HomeModuleCategory.vendas);
      expect(m.permissionKey, 'vendas');
      expect(m.route, '/catalogo_interno');
    });

    test('R6-REG-2 catalogo_loja no atalho e em vendas', () {
      final m = HomeModuleRegistry.byId('catalogo_loja')!;
      expect(m.category, HomeModuleCategory.vendas);
      expect(HomeQuickActionsRow.ids, contains('catalogo_loja'));
    });

    test('R6.1-REG-3 quick actions: Clientes no lugar de Carrinhos', () {
      expect(HomeQuickActionsRow.ids, ['vendas', 'estoque', 'clientes', 'catalogo_loja']);
      expect(HomeQuickActionsRow.ids, isNot(contains('carrinhos_abandonados')));
      expect(HomeModuleRegistry.byId('carrinhos_abandonados')!.category,
          HomeModuleCategory.vendas);
    });
  });
}
