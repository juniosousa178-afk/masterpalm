// Nathy P0: registrarVendaMulti must forward backendItems (original cart roots)
// to baixarEstoqueTransactionBatchIdempotente — otherwise live StateError.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';

Produto _lacinho({
  required String sizeSold,
}) {
  return Produto(
    nome: 'Anel Lacinho Encanto',
    custoReal: 0,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 52.9,
    quantidade: 2,
    precoUnitario: 52.9,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 1, 1),
    idFirebase: 'nathy-pratas-e-folheados-anel-lacinho-encanto',
    lojaId: 'nathy-pratas-e-folheados',
    stockRevision: 8,
    confirmedStockOperationId: 'a8f4df1a-3b8f-4412-b470-be4ee5b3d6a0',
    tamanhos: const ['15', '22'],
    estoquePorTamanho: const {'15': 1, '22': 1},
    variacoes: {
      '15': {'sem-cor': 1},
      '22': {'sem-cor': 1},
    },
  );
}

VendaItem _linha({
  required String productId,
  required String nome,
  required int qty,
  String tamanho = '',
  String cor = '',
}) {
  return VendaItem(
    produtoNome: nome,
    quantidade: qty,
    precoUnitario: 52.9,
    tamanho: tamanho,
    cor: cor,
    productId: productId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
  });

  group('original backend items required', () {
    test('null backendItems throws exact StateError', () async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      await expectLater(
        () => EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
          lojaId: 'nathy-pratas-e-folheados',
          itens: [
            {
              'produtoId': 'nathy-pratas-e-folheados-anel-lacinho-encanto',
              'quantidade': 1,
              'tamanho': '15',
              'cor': 'sem-cor',
            }
          ],
          operationId: 'op-missing-originals',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('itens originais ao servidor'),
          ),
        ),
      );
    });
  });

  group('Lacinho size 15 / 22 snapshot', () {
    for (final size in ['15', '22']) {
      test('montarItensParaBackend preserves $size|sem-cor qty=1', () {
        final produto = _lacinho(sizeSold: size);
        final item = _linha(
          productId: produto.idFirebase,
          nome: produto.nome,
          qty: 1,
          tamanho: size,
          cor: 'sem-cor',
        );
        final roots = VendaComboEstoqueExpansion.montarItensParaBackend(
          itens: [item],
          produtos: [produto],
        );
        expect(roots, hasLength(1));
        expect(roots.single['productId'], produto.idFirebase);
        expect(roots.single['quantity'], 1);
        expect(roots.single['size'], size);
        expect(roots.single['color'], 'sem-cor');

        // Immutable snapshot style used by VendasService.
        final snap = List<Map<String, dynamic>>.unmodifiable(
          roots.map((r) => Map<String, dynamic>.unmodifiable(
                Map<String, dynamic>.from(r),
              )),
        );
        expect(snap.single['size'], size);
        expect(
          () => snap.single['size'] = 'hack',
          throwsUnsupportedError,
        );
      });
    }

    test('idempotent baixa with backendItems reaches stockCatalogCommand',
        () async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      Map<String, dynamic>? seenPayload;
      StockCatalogBackendService.debugTransport = (name, data) async {
        expect(name, 'stockCatalogCommand');
        seenPayload = Map<String, dynamic>.from(data);
        return {
          'operationId': data['operationId'],
          'alreadyApplied': false,
          'products': [
            {
              'productId': 'nathy-pratas-e-folheados-anel-lacinho-encanto',
              'quantidade': 1,
              'stockRevision': 9,
              'stockOperationId': data['operationId'],
              'variacoes': {
                '15': {'sem-cor': 0},
                '22': {'sem-cor': 1},
              },
              'estoquePorTamanho': {'15': 0, '22': 1},
            }
          ],
        };
      };

      final produto = _lacinho(sizeSold: '15');
      final item = _linha(
        productId: produto.idFirebase,
        nome: produto.nome,
        qty: 1,
        tamanho: '15',
        cor: 'sem-cor',
      );
      final backendItems = VendaComboEstoqueExpansion.montarItensParaBackend(
        itens: [item],
        produtos: [produto],
      );
      final txItems =
          VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
        itensParaEstoque: [item],
        produtosEncontrados: [produto],
      );

      final result =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: 'nathy-pratas-e-folheados',
        itens: txItems,
        operationId: 'sale-lacinho-15',
        backendItems: backendItems,
      );

      expect(result.transactionResults, hasLength(1));
      expect(seenPayload, isNotNull);
      expect(seenPayload!['kind'], 'sale');
      final items = seenPayload!['items'] as List;
      expect(items, hasLength(1));
      expect(items.single['size'], '15');
      expect(items.single['color'], 'sem-cor');
      expect(items.single['quantity'], 1);
      // Single decrement payload — not duplicated roots+tx.
      expect(items, hasLength(1));
    });
  });

  group('simple + multi-item original items', () {
    test('simple sale backend item has empty size/color ok', () {
      final p = Produto(
        nome: 'Produto Simples',
        custoReal: 0,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 5,
        precoUnitario: 10,
        categoria: 'X',
        dataEntrada: DateTime(2026, 1, 1),
        idFirebase: 'nathy-simple-1',
        lojaId: 'nathy-pratas-e-folheados',
        stockRevision: 1,
        confirmedStockOperationId: 'op-s',
      );
      final item = _linha(
        productId: p.idFirebase,
        nome: p.nome,
        qty: 1,
      );
      final roots = VendaComboEstoqueExpansion.montarItensParaBackend(
        itens: [item],
        produtos: [p],
      );
      expect(roots.single['productId'], 'nathy-simple-1');
      expect(roots.single['quantity'], 1);
    });

    test('multi-item preserves both identities', () {
      final simple = Produto(
        nome: 'Simples',
        custoReal: 0,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 5,
        precoUnitario: 10,
        categoria: 'X',
        dataEntrada: DateTime(2026, 1, 1),
        idFirebase: 'nathy-simple-1',
        lojaId: 'nathy-pratas-e-folheados',
      );
      final lacinho = _lacinho(sizeSold: '15');
      final itens = [
        _linha(productId: simple.idFirebase, nome: simple.nome, qty: 1),
        _linha(
          productId: lacinho.idFirebase,
          nome: lacinho.nome,
          qty: 1,
          tamanho: '15',
          cor: 'sem-cor',
        ),
      ];
      final roots = VendaComboEstoqueExpansion.montarItensParaBackend(
        itens: itens,
        produtos: [simple, lacinho],
      );
      expect(roots, hasLength(2));
      expect(roots[0]['productId'], 'nathy-simple-1');
      expect(roots[1]['productId'], lacinho.idFirebase);
      expect(roots[1]['size'], '15');
      expect(roots[1]['color'], 'sem-cor');
    });

    test('combo: backendItems = root do combo (não componentes expandidos)', () {
      final combo = Produto(
        nome: 'Combo Nathy',
        custoReal: 0,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 99,
        quantidade: 1,
        precoUnitario: 99,
        categoria: 'Combo',
        dataEntrada: DateTime(2026, 1, 1),
        idFirebase: 'nathy-combo-1',
        lojaId: 'nathy-pratas-e-folheados',
        tipoProduto: 'combo',
        comboConfig: {
          'grupos': [
            {
              'id': 'g1',
              'nome': 'Peças',
              'itens': [
                {'productId': 'comp-a', 'qty': 1},
                {'productId': 'comp-b', 'qty': 1},
              ],
            },
          ],
        },
      );
      final itens = [
        _linha(productId: combo.idFirebase, nome: combo.nome, qty: 1),
      ];
      final roots = VendaComboEstoqueExpansion.montarItensParaBackend(
        itens: itens,
        produtos: [combo],
      );
      expect(roots, hasLength(1), reason: 'COMBO_BACKEND_ROOT_ITEMS_PASS');
      expect(roots.single['productId'], 'nathy-combo-1');
      expect(roots.single['quantity'], 1);
      expect(
        roots.any((e) => e['productId'] == 'comp-a' || e['productId'] == 'comp-b'),
        isFalse,
        reason: 'BACKEND_ITEMS_NOT_TX_EXPANDED',
      );
    });
  });

  group('UX mapping', () {
    test('StateError itens originais NÃO vira conflito de estoque', () {
      final msg = formatSalvarVendaErrorForUser(
        StateError('A venda precisa enviar os itens originais ao servidor.'),
      );
      expect(msg.toLowerCase(), isNot(contains('atualizados')));
      expect(msg.toLowerCase(), isNot(contains('itens originais')));
      expect(msg, contains('Não foi possível concluir a venda'));
    });

    test('failed-precondition stock ainda mapeia para atualizar tela', () {
      final msg = formatSalvarVendaErrorForUser(
        FirebaseException(
          plugin: 'cloud_functions',
          code: 'failed-precondition',
          message: 'Stock revision conflict',
        ),
      );
      expect(msg.toLowerCase(), contains('atualize'));
    });
  });
}
