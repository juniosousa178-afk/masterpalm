import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/features/categories/category_tree.dart';
import 'package:master_palm/features/categories/product_category_fields.dart';
import 'package:master_palm/features/categories/widgets/product_category_assignments_editor.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';

import 'category_tree_test.dart' show doc;

/// A = Feminino > Colar > Colar Prata 925; B = Religioso > Colar > Colar Prata 925 > Cruz;
/// C = Presentes > Dia das Mães; Masculino sem produtos do fixture.
List<Map<String, dynamic>> _docs({List<String> relLegacyNames = const []}) => [
      doc('cat_fem', 'Feminino'),
      doc('cat_fcol', 'Colar', parentId: 'cat_fem'),
      doc('cat_fp925', 'Colar Prata 925', parentId: 'cat_fcol'),
      doc('cat_rel', 'Religioso', legacyNames: relLegacyNames),
      doc('cat_rcol', 'Colar', parentId: 'cat_rel'),
      doc('cat_rp925', 'Colar Prata 925', parentId: 'cat_rcol'),
      doc('cat_cruz', 'Cruz', parentId: 'cat_rp925'),
      doc('cat_pres', 'Presentes'),
      doc('cat_mae', 'Dia das Mães', parentId: 'cat_pres'),
      doc('cat_masc', 'Masculino'),
    ];

CategoryTree _tree({Iterable<CategoryProductRef> products = const []}) =>
    CategoryTree.build(lojaId: 'mirjoias', docs: _docs(), products: products);

ProductCategoryAssignment _a(CategoryTree t, String id) =>
    ProductCategoryAssignment.fromNode(t.node(id)!);

/// Documento do catálogo como o servidor projeta (categoria de texto = primeiro caminho).
Map<String, dynamic> _colarCruzDoc(CategoryTree t, {bool withGifts = false}) => {
      'productId': 'colar-cruz',
      'nome': 'Colar Cruz',
      'categoria': 'Feminino',
      'subcategoria': 'Colar',
      'categoryId': 'cat_fp925',
      'categoryPathIds': t.node('cat_fp925')!.pathIds,
      'categoryPathNames': t.node('cat_fp925')!.pathNames,
      'categoryAssignments': [
        _a(t, 'cat_fp925').toMap(),
        _a(t, 'cat_cruz').toMap(),
        if (withGifts) _a(t, 'cat_mae').toMap(),
      ],
    };

const _sevenNodes = [
  'cat_fem', 'cat_fcol', 'cat_fp925', //
  'cat_rel', 'cat_rcol', 'cat_rp925', 'cat_cruz',
];

void main() {
  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
    ProdutoStockCatalogCadastroSync.debugResetCategoryFieldSupport();
  });

  group('fixture Colar Cruz (§23/§24)', () {
    test('um documento em dois caminhos aparece nos 7 nós; contagem 1 em cada', () {
      final base = _tree();
      final ref = CategoryProductRef.fromMap(_colarCruzDoc(base));
      final t = _tree(products: [ref]);
      expect(t.idsForProduct(ref), _sevenNodes.toSet());
      for (final id in _sevenNodes) {
        expect(t.productMatches(ref, id), isTrue, reason: id);
        expect(t.productCount(id), 1, reason: id);
      }
      expect(t.productMatches(ref, 'cat_masc'), isFalse);
      expect(t.productMatches(ref, 'cat_pres'), isFalse);
    });

    test('três ramos independentes: 9 nós, um único produto', () {
      final base = _tree();
      final ref = CategoryProductRef.fromMap(_colarCruzDoc(base, withGifts: true));
      final t = _tree(products: [ref]);
      expect(t.idsForProduct(ref), {..._sevenNodes, 'cat_pres', 'cat_mae'});
      expect(t.productCount('cat_mae'), 1);
    });

    test('filtro do catálogo (lista de docs): cada nó lista o produto uma vez (dedupe por id)', () {
      final base = _tree();
      final docs = [
        _colarCruzDoc(base),
        {'productId': 'anel-masc', 'nome': 'Anel', 'categoria': 'Masculino'},
      ];
      final t = _tree(products: docs.map((d) => CategoryProductRef.fromMap(d, skipComboLabel: true)));
      for (final id in _sevenNodes) {
        final hits = docs
            .where((d) => t.productMatches(CategoryProductRef.fromMap(d, skipComboLabel: true), id))
            .map((d) => d['productId'])
            .toList();
        expect(hits, ['colar-cruz'], reason: id);
      }
    });

    test('busca + categoria: "cruz" em Religioso > Colar e em Feminino acha o mesmo produto', () {
      final base = _tree();
      final docs = [
        _colarCruzDoc(base),
        {'productId': 'pulseira', 'nome': 'Pulseira Cruz', 'categoria': 'Masculino'},
      ];
      final t = _tree(products: docs.map((d) => CategoryProductRef.fromMap(d)));
      List<Object?> search(String q, String nodeId) => docs
          .where((d) => (d['nome'] as String).toLowerCase().contains(q))
          .where((d) => t.productMatches(CategoryProductRef.fromMap(d), nodeId))
          .map((d) => d['productId'])
          .toList();
      expect(search('cruz', 'cat_rcol'), ['colar-cruz']);
      expect(search('cruz', 'cat_fem'), ['colar-cruz']);
      expect(search('cruz', 'cat_masc'), ['pulseira']);
    });

    test('menu do catálogo: raiz do segundo caminho entra mesmo sem texto de categoria', () {
      final base = _tree();
      final t = _tree(products: [CategoryProductRef.fromMap(_colarCruzDoc(base))]);
      final roots = t.rootNamesWithProducts();
      expect(roots, containsAll(['Feminino', 'Religioso']));
      expect(roots, isNot(contains('Masculino')));
      expect(roots, isNot(contains('Presentes')));
      final menu = t.nodeByNamePath(['Religioso', 'Colar', 'Colar Prata 925', 'Cruz']);
      expect(menu?.id, 'cat_cruz');
    });

    test('filtro do estoque (Produto do Hive): mesmo resultado, um produto por id', () {
      final base = _tree();
      final p = Produto.vazio()
        ..idFirebase = 'colar-cruz'
        ..nome = 'Colar Cruz'
        ..categoria = 'Feminino'
        ..subcategoria = 'Colar';
      ProductCategoryFields.setAssignments(p, [_a(base, 'cat_fp925'), _a(base, 'cat_cruz')]);
      final outro = Produto.vazio()
        ..idFirebase = 'anel'
        ..categoria = 'Masculino';
      final produtos = [p, outro];
      final t = _tree(products: produtos.map(CategoryProductRef.fromProduto));
      for (final id in _sevenNodes) {
        final hits = produtos
            .where((x) => t.productMatches(CategoryProductRef.fromProduto(x), id))
            .map((x) => x.idFirebase)
            .toList();
        expect(hits, ['colar-cruz'], reason: id);
      }
      expect(
          produtos.where((x) => t.productMatches(CategoryProductRef.fromProduto(x), 'cat_masc')).length,
          1);
    });
  });

  group('compatibilidade legado (§9/§10)', () {
    test('produto só com o trio vale como uma atribuição (sem migração)', () {
      final base = _tree();
      final legado = Produto.vazio()
        ..categoryId = 'cat_fp925'
        ..categoryPathIds = base.node('cat_fp925')!.pathIds
        ..categoryPathNames = base.node('cat_fp925')!.pathNames;
      final list = ProductCategoryFields.assignmentsOf(legado);
      expect(list.single.categoryId, 'cat_fp925');
      expect(legado.categoryAssignments, isEmpty);
      final ref = CategoryProductRef.fromProduto(legado);
      expect(_tree(products: [ref]).idsForProduct(ref), {'cat_fem', 'cat_fcol', 'cat_fp925'});
    });

    test('atribuições não vazias são a fonte; trio divergente é ignorado na leitura', () {
      final base = _tree();
      final data = {
        'categoryId': 'cat_masc',
        'categoryPathIds': ['cat_masc'],
        'categoryPathNames': ['Masculino'],
        'categoryAssignments': [_a(base, 'cat_cruz').toMap()],
      };
      expect(ProductCategoryFields.assignmentsFromMap(data).map((a) => a.categoryId), ['cat_cruz']);
      final ref = CategoryProductRef.fromMap(data);
      expect(_tree(products: [ref]).productMatches(ref, 'cat_masc'), isFalse);
    });

    test('produto só com texto continua visível (nós virtuais) e não ganha caminho', () {
      const ref = CategoryProductRef(categorias: ['Brincos'], subcategorias: ['Argola']);
      final t = _tree(products: const [ref]);
      final virtual = t.nodeByNamePath(['Brincos', 'Argola']);
      expect(virtual, isNotNull);
      expect(virtual!.isVirtual, isTrue);
      expect(t.productMatches(ref, virtual.id), isTrue);
      expect(t.rootNamesWithProducts(), isNot(contains('Brincos')));
      expect(ProductCategoryFields.assignmentsOf(Produto.vazio()..categoria = 'Brincos'), isEmpty);
    });

    test('zero categorias: produto sem caminho e sem texto não aparece em nenhum nó', () {
      final p = Produto.vazio();
      ProductCategoryFields.setAssignments(p, const []);
      expect(p.categoryId, '');
      expect(p.categoryAssignments, isEmpty);
      final ref = CategoryProductRef.fromProduto(p);
      expect(_tree(products: [ref]).idsForProduct(ref), isEmpty);
      expect(ProductCategoryFields.toFullMap(p)['categoryAssignments'], isEmpty);
    });
  });

  group('normalização e edição (§5/§6/§8/§21/§26)', () {
    test('folha repetida vira uma; ancestral de outra folha sai; ramos independentes ficam', () {
      final t = _tree();
      final out = ProductCategoryFields.normalize([
        _a(t, 'cat_fp925'),
        _a(t, 'cat_rcol'),
        _a(t, 'cat_fp925'),
        _a(t, 'cat_cruz'),
        _a(t, 'cat_fem'),
        _a(t, 'cat_mae'),
      ]);
      expect(out.map((a) => a.categoryId), ['cat_fp925', 'cat_cruz', 'cat_mae']);
    });

    test('Adicionar: duplicata, ancestral coberto, descendente substitui, limite, virtual', () {
      final t = _tree();
      var cur = [_a(t, 'cat_fp925')];
      var r = ProductCategoryFields.addAssignment(cur, t.node('cat_cruz')!);
      expect(r.outcome, CategoryAddOutcome.added);
      cur = r.assignments;
      expect(cur.map((a) => a.categoryId), ['cat_fp925', 'cat_cruz']);

      r = ProductCategoryFields.addAssignment(cur, t.node('cat_cruz')!);
      expect(r.outcome, CategoryAddOutcome.duplicate);
      expect(r.assignments, same(cur));

      r = ProductCategoryFields.addAssignment(cur, t.node('cat_rel')!);
      expect(r.outcome, CategoryAddOutcome.coveredByDescendant);

      r = ProductCategoryFields.addAssignment([_a(t, 'cat_rcol'), _a(t, 'cat_mae')], t.node('cat_cruz')!);
      expect(r.outcome, CategoryAddOutcome.replacedAncestor);
      expect(r.assignments.map((a) => a.categoryId), ['cat_cruz', 'cat_mae']);

      final full = [
        for (var i = 0; i < kMaxCategoryAssignments; i++)
          ProductCategoryAssignment(categoryId: 'c$i', pathIds: ['c$i'], pathNames: ['C$i']),
      ];
      r = ProductCategoryFields.addAssignment(full, t.node('cat_masc')!);
      expect(r.outcome, CategoryAddOutcome.limitReached);
      expect(r.assignments, hasLength(kMaxCategoryAssignments));

      final virtual = CategoryTree.build(
        lojaId: 'mirjoias',
        docs: const [],
        products: const [CategoryProductRef(categorias: ['Brincos'])],
      ).roots.single;
      r = ProductCategoryFields.addAssignment(cur, virtual);
      expect(r.outcome, CategoryAddOutcome.virtualNode);
    });

    test('limite explícito: 20 caminhos e mensagem clara', () {
      expect(kMaxCategoryAssignments, 20);
      expect(kCategoryAssignmentsLimitMessage, 'Um produto pode estar em até 20 categorias.');
    });

    test('remover um caminho só tira o vínculo: estoque, preço, SKU e id intactos', () {
      final t = _tree();
      final p = Produto.vazio()
        ..idFirebase = 'colar-cruz'
        ..sku = 'CC-1'
        ..quantidade = 7
        ..precoSugerido = 129.9;
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz'), _a(t, 'cat_mae')]);
      final next = ProductCategoryFields.removeAssignment(ProductCategoryFields.assignmentsOf(p), 'cat_cruz');
      ProductCategoryFields.setAssignments(p, next);
      expect(ProductCategoryFields.assignmentsOf(p).map((a) => a.categoryId), ['cat_fp925', 'cat_mae']);
      expect(p.categoryId, 'cat_fp925');
      expect([p.idFirebase, p.sku, p.quantidade, p.precoSugerido], ['colar-cruz', 'CC-1', 7, 129.9]);
    });

    test('remover o principal: o próximo caminho vira o trio espelhado', () {
      final t = _tree();
      final p = Produto.vazio();
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz')]);
      ProductCategoryFields.setAssignments(
          p, ProductCategoryFields.removeAssignment(ProductCategoryFields.assignmentsOf(p), 'cat_fp925'));
      expect(p.categoryId, 'cat_cruz');
      expect(p.categoryPathNames, ['Religioso', 'Colar', 'Colar Prata 925', 'Cruz']);
    });

    test('salvar/reabrir/salvar mantém os 3 caminhos (edição não relacionada)', () {
      final t = _tree();
      final p = Produto.vazio()
        ..categoria = 'Feminino'
        ..subcategoria = 'Colar';
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz'), _a(t, 'cat_mae')]);
      for (var i = 0; i < 2; i++) {
        final reopened = ProductCategoryFields.assignmentsOf(p);
        final saved = ProductCategoryFields.assignmentsForSave(
            assignments: reopened, tree: t, categoria: p.categoria, subcategoria: p.subcategoria);
        p.nome = 'Colar Cruz v$i';
        ProductCategoryFields.setAssignments(p, saved);
      }
      expect(ProductCategoryFields.assignmentsOf(p).map((a) => a.categoryId),
          ['cat_fp925', 'cat_cruz', 'cat_mae']);
    });

    test('texto de categoria trocado: só o caminho principal sai', () {
      final t = _tree();
      final saved = ProductCategoryFields.assignmentsForSave(
        assignments: [_a(t, 'cat_fp925'), _a(t, 'cat_cruz')],
        tree: t,
        categoria: 'Masculino',
        subcategoria: '',
      );
      expect(saved.map((a) => a.categoryId), ['cat_cruz']);
    });

    test('rename: nomes atuais da árvore; texto antigo (legacyNames) mantém o vínculo', () {
      final antigo = _tree();
      final gravado = [_a(antigo, 'cat_cruz'), _a(antigo, 'cat_fp925')];
      final renamed = CategoryTree.build(
        lojaId: 'mirjoias',
        docs: [
          for (final d in _docs(relLegacyNames: const ['Religioso']))
            d['id'] == 'cat_rel' ? {...d, 'nome': 'Fé'} : d,
        ],
      );
      final saved = ProductCategoryFields.assignmentsForSave(
          assignments: gravado, tree: renamed, categoria: 'Religioso', subcategoria: 'Colar');
      expect(saved.map((a) => a.categoryId), ['cat_cruz', 'cat_fp925']);
      expect(saved.first.pathNames.first, 'Fé');
      expect(saved.first.pathIds, antigo.node('cat_cruz')!.pathIds);
    });

    test('excluir categoria verifica todos os caminhos (inclusive o não principal)', () {
      final base = _tree();
      final t = _tree(products: [CategoryProductRef.fromMap(_colarCruzDoc(base))]);
      expect(t.archiveBlocker(t.node('cat_cruz')!), kCategoryHasProductsMessage);
      expect(t.archiveBlocker(t.node('cat_fp925')!), kCategoryHasProductsMessage);
      expect(t.archiveBlocker(t.node('cat_mae')!), isNull);
    });
  });

  group('persistência e envio (§16/§17)', () {
    test('toMap (escrita direta com merge) não leva atribuições; toFullMap leva todas', () {
      final t = _tree();
      final p = Produto.vazio();
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz')]);
      final direct = ProductCategoryFields.toMap(p);
      expect(direct.containsKey('categoryAssignments'), isFalse);
      expect(direct['categoryId'], 'cat_fp925');
      final full = ProductCategoryFields.toFullMap(p);
      expect((full['categoryAssignments'] as List).map((m) => (m as Map)['categoryId']),
          ['cat_fp925', 'cat_cruz']);
      expect(full.containsKey('categoryMembershipIds'), isFalse);
      final ed = ProdutoStockCatalogCadastroSync.buildEditorial(p..nome = 'Colar Cruz');
      expect((ed['categoryAssignments'] as List), hasLength(2));
      expect(StockCatalogBackendService.editorialFields.contains('categoryAssignments'), isTrue);
    });

    test('doc antigo sem a chave não apaga; importação com caminhos substitui todos', () {
      final t = _tree();
      final p = Produto.vazio();
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz')]);
      ProductCategoryFields.applyFromMap(p, {'nome': 'X', 'categoryId': 'cat_fp925'});
      expect(p.categoryAssignments, hasLength(2));

      final novo = Produto.vazio();
      ProductCategoryFields.setAssignments(novo, [_a(t, 'cat_mae')]);
      ProductCategoryFields.mergeImported(existente: p, novo: novo);
      expect(ProductCategoryFields.assignmentsOf(p).map((a) => a.categoryId), ['cat_mae']);
    });

    test('importação com texto diferente do principal tira só esse caminho', () {
      final t = _tree();
      final p = Produto.vazio();
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz')]);
      ProductCategoryFields.mergeImported(existente: p, novo: Produto.vazio()..categoria = 'Masculino');
      expect(ProductCategoryFields.assignmentsOf(p).map((a) => a.categoryId), ['cat_cruz']);
    });

    test('Hive: campo 58 (vários caminhos) sobrevive a gravar/ler', () async {
      final dir = await Directory.systemTemp.createTemp('multicat_hive_');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      final box = await Hive.openBox<Produto>('produtos_multicat_test');
      final t = _tree();
      final p = Produto.vazio()..nome = 'Colar Cruz';
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_cruz'), _a(t, 'cat_mae')]);
      await box.put('p1', p);
      await box.close();
      final reopened = await Hive.openBox<Produto>('produtos_multicat_test');
      final r = reopened.get('p1')!;
      expect(ProductCategoryFields.assignmentsOf(r).map((a) => a.categoryId),
          ['cat_fp925', 'cat_cruz', 'cat_mae']);
      expect(r.categoryAssignments[1]['pathNames'], ['Religioso', 'Colar', 'Colar Prata 925', 'Cruz']);
      expect(r.categoryId, 'cat_fp925');
      await reopened.close();
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('resposta do servidor (caminhos canônicos) volta ao Hive; sem a chave, nada muda', () {
      final t = _tree();
      final p = Produto.vazio()..idFirebase = 'colar-cruz';
      ProductCategoryFields.setAssignments(p, [_a(t, 'cat_fp925'), _a(t, 'cat_fp925'), _a(t, 'cat_cruz')]);
      final changed = ProdutoStockCatalogCadastroSync.applyCanonicalCategoryFields(p, {
        'products': [
          {'productId': 'outro', 'categoryAssignments': const []},
          {
            'productId': 'colar-cruz',
            'categoryId': 'cat_fp925',
            'categoryPathIds': t.node('cat_fp925')!.pathIds,
            'categoryPathNames': t.node('cat_fp925')!.pathNames,
            'categoryAssignments': [_a(t, 'cat_fp925').toMap(), _a(t, 'cat_cruz').toMap()],
          },
        ],
      });
      expect(changed, isTrue);
      expect(p.categoryAssignments.map((m) => m['categoryId']), ['cat_fp925', 'cat_cruz']);
      final semChave = ProdutoStockCatalogCadastroSync.applyCanonicalCategoryFields(p, {
        'products': [
          {'productId': 'colar-cruz', 'nome': 'X'},
        ],
      });
      expect(semChave, isFalse);
      expect(p.categoryAssignments, hasLength(2));
    });

    test('servidor sem categoryAssignments: reenvia só sem elas (trio fica) e lembra na sessão', () async {
      final calls = <Map<String, dynamic>>[];
      StockCatalogBackendService.debugTransport = (name, data) async {
        calls.add(Map<String, dynamic>.from(data));
        if ((data['editorial'] as Map).containsKey('categoryAssignments')) {
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
                'categoryId': 'cat_fp925',
                'categoryPathIds': ['cat_fem', 'cat_fcol', 'cat_fp925'],
                'categoryPathNames': ['Feminino', 'Colar', 'Colar Prata 925'],
                'categoryAssignments': [
                  {'categoryId': 'cat_fp925', 'pathIds': ['cat_fem', 'cat_fcol', 'cat_fp925'], 'pathNames': ['Feminino', 'Colar', 'Colar Prata 925']},
                ],
              },
            ),
          );
      await send('op-1');
      expect(calls, hasLength(2));
      expect(calls[1]['operationId'], 'op-1');
      final retried = calls[1]['editorial'] as Map;
      expect(retried.containsKey('categoryAssignments'), isFalse);
      expect(retried['categoryId'], 'cat_fp925');
      await send('op-2');
      expect(calls, hasLength(3));
      expect((calls[2]['editorial'] as Map).containsKey('categoryAssignments'), isFalse);
      expect((calls[2]['editorial'] as Map)['categoryId'], 'cat_fp925');
    });
  });

  group('UI "Categorias do produto" (§7/§29)', () {
    const sizes = <String, Size>{
      '360': Size(360, 740),
      '390': Size(390, 844),
      'tablet': Size(800, 1100),
      'desktop': Size(1366, 800),
    };
    const longName = 'Nossa Senhora Aparecida em Prata 925 com Zircônias Cravejadas';

    CategoryTree longTree() => CategoryTree.build(lojaId: 'mirjoias', docs: [
          ..._docs().where((d) => d['id'] != 'cat_cruz'),
          doc('cat_cruz', longName, parentId: 'cat_rp925'),
        ]);

    Future<void> pump(
      WidgetTester tester, {
      required List<ProductCategoryAssignment> assignments,
      CategoryTree? tree,
      bool primaryLinked = true,
      VoidCallback? onAdd,
      ValueChanged<String>? onRemove,
    }) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ProductCategoryAssignmentsEditor(
                assignments: assignments,
                tree: tree,
                primaryLinked: primaryLinked,
                onAdd: onAdd ?? () {},
                onRemove: onRemove ?? (_) {},
                onManage: () {},
              ),
            ),
          ),
        ));

    for (final entry in sizes.entries) {
      testWidgets('3 caminhos com nome longo em ${entry.key}: cards completos, sem overflow', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final t = longTree();
        final removed = <String>[];
        var adds = 0;
        await pump(
          tester,
          tree: t,
          assignments: [_a(t, 'cat_fp925'), _a(t, 'cat_cruz'), _a(t, 'cat_mae')],
          onAdd: () => adds++,
          onRemove: removed.add,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Categorias do produto'), findsOneWidget);
        for (final id in ['cat_fp925', 'cat_cruz', 'cat_mae']) {
          expect(find.byKey(ValueKey('produto_category_assignment_$id')), findsOneWidget);
        }
        expect(find.textContaining(longName), findsOneWidget);
        expect(find.text('Principal'), findsOneWidget);
        expect(find.text('3 de $kMaxCategoryAssignments'), findsOneWidget);
        final card = tester.getRect(find.byKey(const ValueKey('produto_category_assignment_cat_cruz')));
        expect(card.right, lessThanOrEqualTo(entry.value.width));

        await tester.tap(find.byKey(const ValueKey('produto_category_remove_cat_cruz')));
        await tester.tap(find.byKey(const ValueKey('produto_category_add')));
        expect(removed, ['cat_cruz']);
        expect(adds, 1);
      });
    }

    testWidgets('no limite: Adicionar desabilitado e mensagem explícita', (tester) async {
      final full = [
        for (var i = 0; i < kMaxCategoryAssignments; i++)
          ProductCategoryAssignment(categoryId: 'c$i', pathIds: ['c$i'], pathNames: ['Categoria $i']),
      ];
      await pump(tester, assignments: full);
      final add = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('produto_category_add')));
      expect(add.onPressed, isNull);
      expect(find.text(kCategoryAssignmentsLimitMessage), findsOneWidget);
    });

    testWidgets('principal desvinculado do texto: aviso no card principal', (tester) async {
      final t = _tree();
      await pump(tester, tree: t, primaryLinked: false, assignments: [_a(t, 'cat_fp925'), _a(t, 'cat_cruz')]);
      expect(find.text('Categoria/Subcategoria foi alterada: este caminho sai ao salvar.'), findsOneWidget);
      expect(find.text('Principal'), findsNothing);
    });

    testWidgets('sem caminhos: "Nenhuma categoria escolhida."', (tester) async {
      await pump(tester, assignments: const []);
      expect(find.text('Nenhuma categoria escolhida.'), findsOneWidget);
      expect(find.byKey(const ValueKey('produto_category_count')), findsNothing);
    });
  });
}
