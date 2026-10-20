import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/features/categories/category_service.dart';
import 'package:master_palm/features/categories/category_tree.dart';
import 'package:master_palm/features/categories/product_category_fields.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

import 'category_tree_test.dart' show doc, sixLevels;

void main() {
  tearDown(() {
    CategoryService.debugReset();
    StockCatalogBackendService.debugTransport = null;
    ProdutoStockCatalogCadastroSync.debugResetCategoryFieldSupport();
  });

  group('CategoryService', () {
    test('uma consulta por loja; árvore montada em memória e cacheada', () async {
      final loads = <String>[];
      CategoryService.debugLoadDocs = (loja) async {
        loads.add(loja);
        return sixLevels(lojaId: loja);
      };
      final t1 = await CategoryService.loadTree('mirjoias');
      final t2 = await CategoryService.loadTree('mirjoias');
      expect(loads, ['mirjoias']);
      expect(t1.node('cat_crav')!.depth, 6);
      expect(t2.activeNodes.length, 7);
      await CategoryService.loadTree('mirjoias', refresh: true);
      expect(loads, ['mirjoias', 'mirjoias']);
    });

    test('criar filho de N6: bloqueado antes do servidor (0 chamadas)', () async {
      final calls = <Map<String, dynamic>>[];
      CategoryService.debugTransport = (data) async {
        calls.add(data);
        return {'ok': true};
      };
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
      await expectLater(
        CategoryService.create(
            lojaId: 'mirjoias', tree: tree, parent: tree.node('cat_crav'), nome: 'Sétimo'),
        throwsA(isA<CategoryException>()
            .having((e) => e.code, 'code', CategoryException.depthLimit)
            .having((e) => e.message, 'message', kCategoryDepthLimitMessage)),
      );
      expect(calls, isEmpty);
    });

    test('criar N6 envia comando com protocolo, loja, pai e operationId', () async {
      final calls = <Map<String, dynamic>>[];
      CategoryService.debugTransport = (data) async {
        calls.add(data);
        return {'ok': true};
      };
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
      await CategoryService.create(
          lojaId: 'mirjoias', tree: tree, parent: tree.node('cat_p925'), nome: '  Lisos  ');
      expect(calls, hasLength(1));
      final c = calls.single;
      expect(c['protocolVersion'], 1);
      expect(c['lojaId'], 'mirjoias');
      expect(c['operation'], 'create');
      expect((c['operationId'] as String).startsWith('cat_create_'), isTrue);
      expect(c['payload'], {
        'parent': {'id': 'cat_p925'},
        'nome': 'Lisos',
      });
    });

    test('excluir com filhos ou produtos: bloqueado localmente (0 chamadas)', () async {
      var calls = 0;
      CategoryService.debugTransport = (data) async {
        calls++;
        return {'ok': true};
      };
      final tree = CategoryTree.build(
        lojaId: 'mirjoias',
        docs: sixLevels(),
        products: const [CategoryProductRef(pathIds: ['cat_masc'])],
      );
      await expectLater(
        CategoryService.archive(lojaId: 'mirjoias', tree: tree, node: tree.node('cat_fem')!),
        throwsA(isA<CategoryException>()
            .having((e) => e.code, 'code', CategoryException.hasChildren)
            .having((e) => e.message, 'message', 'Esta categoria possui subcategorias.')),
      );
      await expectLater(
        CategoryService.archive(lojaId: 'mirjoias', tree: tree, node: tree.node('cat_masc')!),
        throwsA(isA<CategoryException>()
            .having((e) => e.code, 'code', CategoryException.hasProducts)),
      );
      expect(calls, 0);
    });

    test('erro do servidor com categoryCode vira CategoryException', () async {
      CategoryService.debugTransport = (data) async => throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Esta categoria possui subcategorias.',
            details: {'categoryCode': 'CATEGORY_HAS_CHILDREN'},
          );
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [doc('cat_x', 'X')]);
      await expectLater(
        CategoryService.archive(lojaId: 'mirjoias', tree: tree, node: tree.node('cat_x')!),
        throwsA(isA<CategoryException>()
            .having((e) => e.code, 'code', 'CATEGORY_HAS_CHILDREN')),
      );
    });

    test('servidor sem a função: mensagem de indisponível', () async {
      CategoryService.debugTransport =
          (data) async => throw FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: const []);
      await expectLater(
        CategoryService.create(lojaId: 'mirjoias', tree: tree, parent: null, nome: 'Feminino'),
        throwsA(isA<CategoryException>()
            .having((e) => e.code, 'code', CategoryException.notAvailable)),
      );
    });

    test('nó virtual (só texto legado) vai como legacyPath', () async {
      final calls = <Map<String, dynamic>>[];
      CategoryService.debugTransport = (data) async {
        calls.add(data);
        return {'ok': true};
      };
      final tree = CategoryTree.build(
        lojaId: 'mirjoias',
        docs: const [],
        products: const [CategoryProductRef(categorias: ['Anéis'], subcategorias: ['Prata'])],
      );
      final prata = tree.childrenOf(tree.roots.single.id).single;
      await CategoryService.create(lojaId: 'mirjoias', tree: tree, parent: prata, nome: 'Lisos');
      expect(calls.single['payload']['parent'], {'legacyPath': ['Anéis', 'Prata']});
    });
  });

  group('ProductCategoryFields', () {
    CategoryNode aneis() =>
        CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels()).node('cat_ane')!;

    test('seleção grava folha + caminho; virtual/nenhum limpa', () {
      final p = Produto.vazio();
      ProductCategoryFields.applySelection(p, aneis());
      expect(p.categoryId, 'cat_ane');
      expect(p.categoryPathIds, ['cat_fem', 'cat_rel', 'cat_ane']);
      expect(p.categoryPathNames, ['Feminino', 'Religioso', 'Anéis']);
      ProductCategoryFields.applySelection(p, null);
      expect(p.categoryId, '');
      expect(p.categoryPathIds, isEmpty);
    });

    test('toMap coerente; trio inconsistente vai vazio (servidor aceita)', () {
      final p = Produto.vazio();
      ProductCategoryFields.applySelection(p, aneis());
      expect(ProductCategoryFields.toMap(p), {
        'categoryId': 'cat_ane',
        'categoryPathIds': ['cat_fem', 'cat_rel', 'cat_ane'],
        'categoryPathNames': ['Feminino', 'Religioso', 'Anéis'],
      });
      p.categoryId = 'cat_outro';
      expect(ProductCategoryFields.toMap(p)['categoryPathIds'], isEmpty);
      expect(ProductCategoryFields.toMap(Produto.vazio())['categoryId'], '');
    });

    test('applyFromMap só aplica chaves presentes (doc antigo não apaga)', () {
      final p = Produto.vazio();
      ProductCategoryFields.applySelection(p, aneis());
      ProductCategoryFields.applyFromMap(p, {'nome': 'X'});
      expect(p.categoryId, 'cat_ane');
      ProductCategoryFields.applyFromMap(p, {
        'categoryId': 'cat_masc',
        'categoryPathIds': ['cat_masc'],
        'categoryPathNames': ['Masculino'],
      });
      expect(p.categoryPathNames, ['Masculino']);
    });

    test('caminho só vale se categoria/subcategoria de texto concordarem', () {
      const names = ['Feminino', 'Religioso', 'Anéis'];
      expect(ProductCategoryFields.pathAgreesWithText(names, 'feminino', 'RELIGIOSO'), isTrue);
      expect(ProductCategoryFields.pathAgreesWithText(names, 'Feminino', ''), isFalse);
      expect(ProductCategoryFields.pathAgreesWithText(names, 'Masculino', 'Religioso'), isFalse);
      expect(ProductCategoryFields.pathAgreesWithText(const ['Masculino'], 'Masculino', ''), isTrue);
      expect(ProductCategoryFields.pathAgreesWithText(const [], 'X', ''), isFalse);
    });

    test('importação: caminho novo substitui; texto diferente invalida; texto vazio preserva', () {
      final existente = Produto.vazio();
      ProductCategoryFields.applySelection(existente, aneis());
      ProductCategoryFields.mergeImported(existente: existente, novo: Produto.vazio());
      expect(existente.categoryId, 'cat_ane');
      ProductCategoryFields.mergeImported(
          existente: existente, novo: Produto.vazio()..categoria = 'Feminino'..subcategoria = 'Religioso');
      expect(existente.categoryId, 'cat_ane');
      ProductCategoryFields.mergeImported(
          existente: existente, novo: Produto.vazio()..categoria = 'Masculino');
      expect(existente.categoryId, '');
    });

    test('Hive: campos 55–57 sobrevivem a gravar/ler', () async {
      final dir = await Directory.systemTemp.createTemp('cat_hive_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      final box = await Hive.openBox<Produto>('produtos_cat_test');
      final p = Produto.vazio()..nome = 'Anel Nossa Senhora';
      ProductCategoryFields.applySelection(p, aneis());
      await box.put('p1', p);
      await box.close();
      final reopened = await Hive.openBox<Produto>('produtos_cat_test');
      final r = reopened.get('p1')!;
      expect(r.categoryId, 'cat_ane');
      expect(r.categoryPathIds, ['cat_fem', 'cat_rel', 'cat_ane']);
      expect(r.categoryPathNames, ['Feminino', 'Religioso', 'Anéis']);
      await reopened.close();
      await Hive.close();
      await dir.delete(recursive: true);
    });
  });

  group('envio editorial', () {
    test('buildEditorial inclui o trio e o cliente o reconhece como editorial', () {
      final p = Produto.vazio()
        ..nome = 'Anel'
        ..publicadoNoCatalogo = true;
      ProductCategoryFields.applySelection(
          p, CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels()).node('cat_ane'));
      final ed = ProdutoStockCatalogCadastroSync.buildEditorial(p);
      expect(ed['categoryId'], 'cat_ane');
      expect(ed['categoryPathIds'], ['cat_fem', 'cat_rel', 'cat_ane']);
      for (final k in ProductCategoryFields.keys) {
        expect(StockCatalogBackendService.editorialFields.contains(k), isTrue);
      }
    });

    test('servidor antigo recusa o trio: reenvia sem ele (mesmo operationId) e lembra na sessão', () async {
      final calls = <Map<String, dynamic>>[];
      StockCatalogBackendService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        if ((data['editorial'] as Map).containsKey('categoryId')) {
          throw FirebaseFunctionsException(
              code: 'invalid-argument', message: 'Protected or unknown editorial field');
        }
        return {'operationId': data['operationId'], 'alreadyApplied': false, 'products': const []};
      };
      Future<void> send(String op) => ProdutoStockCatalogCadastroSync.sendIntent(
            lojaId: 'loja',
            intent: ProdutoStockCatalogCadastroIntent(
              operationId: op,
              kind: 'editorial',
              items: const [{'productId': 'p'}],
              editorial: const {
                'nome': 'X',
                'codigoBarras': '789',
                'categoryId': 'cat_ane',
                'categoryPathIds': ['cat_fem', 'cat_rel', 'cat_ane'],
                'categoryPathNames': ['Feminino', 'Religioso', 'Anéis'],
              },
            ),
          );
      await send('op-1');
      expect(calls, hasLength(2));
      expect(calls[1]['operationId'], 'op-1');
      final retried = calls[1]['editorial'] as Map;
      expect(retried.containsKey('categoryId'), isFalse);
      expect(retried['codigoBarras'], '789');
      await send('op-2');
      expect(calls, hasLength(3));
      expect((calls[2]['editorial'] as Map).containsKey('categoryId'), isFalse);
    });

    test('servidor sem trio e sem identidade: remove os dois em etapas', () async {
      final calls = <Map<String, dynamic>>[];
      StockCatalogBackendService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        final ed = data['editorial'] as Map;
        if (ed.containsKey('categoryId') || ed.containsKey('codigoBarras')) {
          throw FirebaseFunctionsException(
              code: 'invalid-argument', message: 'Protected or unknown editorial field');
        }
        return {'operationId': data['operationId'], 'alreadyApplied': false, 'products': const []};
      };
      await ProdutoStockCatalogCadastroSync.sendIntent(
        lojaId: 'loja',
        intent: ProdutoStockCatalogCadastroIntent(
          operationId: 'op-3',
          kind: 'editorial',
          items: const [{'productId': 'p'}],
          editorial: const {
            'nome': 'X',
            'codigoBarras': '789',
            'categoryId': '',
            'categoryPathIds': <String>[],
            'categoryPathNames': <String>[],
          },
        ),
      );
      expect(calls, hasLength(3));
      expect(calls.map((c) => c['operationId']).toSet(), {'op-3'});
      expect((calls[2]['editorial'] as Map).keys, ['nome']);
    });
  });
}
