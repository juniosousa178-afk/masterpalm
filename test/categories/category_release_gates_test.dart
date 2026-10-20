import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/categories/category_tree.dart';
import 'package:master_palm/features/categories/product_category_fields.dart';
import 'package:master_palm/models/produto.dart';

import 'category_tree_test.dart' show doc, sixLevels;

Produto _filed(CategoryNode node) {
  final p = Produto.vazio()
    ..nome = 'Anel Nossa Senhora'
    ..categoria = node.pathNames.first
    ..subcategoria = node.pathNames.length > 1 ? node.pathNames[1] : '';
  ProductCategoryFields.applySelection(p, node);
  return p;
}

({String id, List<String> pathIds, List<String> pathNames}) _save(Produto p, CategoryTree tree) =>
    ProductCategoryFields.choiceForSave(
      categoryId: p.categoryId,
      pathIds: p.categoryPathIds,
      pathNames: p.categoryPathNames,
      current: tree.node(p.categoryId),
      categoria: p.categoria,
      subcategoria: p.subcategoria,
    );

Produto _reopen(Produto saved) {
  final map = {
    'categoria': saved.categoria,
    'subcategoria': saved.subcategoria,
    ...ProductCategoryFields.toMap(saved),
  };
  final p = Produto.vazio()
    ..categoria = map['categoria'] as String
    ..subcategoria = map['subcategoria'] as String;
  ProductCategoryFields.applyFromMap(p, map);
  return p;
}

List<Map<String, dynamic>> _renamed(String id, String nome, String old) => [
      for (final d in sixLevels())
        d['id'] == id ? {...d, 'nome': nome, 'legacyNames': [old]} : d,
    ];

void main() {
  test('roundtrip Feminino > Religioso > Anéis: salvar, reabrir, salvar mantém o trio (CATEGORY_PRODUCT_ROUNDTRIP_PASS)', () {
    final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
    final p = _filed(tree.node('cat_ane')!);
    final first = _save(p, tree);
    expect(first.id, 'cat_ane');
    expect(first.pathIds, ['cat_fem', 'cat_rel', 'cat_ane']);
    final reopened = _reopen(p);
    final second = _save(reopened, tree);
    expect(second.id, first.id);
    expect(second.pathIds, first.pathIds);
    expect(second.pathNames, first.pathNames);
    expect(ProductCategoryFields.toMap(reopened), ProductCategoryFields.toMap(p));
  });

  test('rename de nível 2: ids estáveis, nome atual exibido e vínculo preservado após salvar/reabrir', () {
    final tree0 = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
    final p = _filed(tree0.node('cat_ane')!);
    final tree = CategoryTree.build(lojaId: 'mirjoias', docs: _renamed('cat_rel', 'Religiosos', 'Religioso'));
    final ref = CategoryProductRef.fromProduto(p);

    expect(tree.node('cat_rel')!.id, 'cat_rel');
    expect(tree.node(p.categoryId)!.pathNames, ['Feminino', 'Religiosos', 'Anéis']);
    expect(p.categoryPathNames, ['Feminino', 'Religioso', 'Anéis'], reason: 'produto não é reescrito');
    for (final id in ['cat_fem', 'cat_rel', 'cat_ane']) {
      expect(tree.productMatches(ref, id), isTrue, reason: id);
    }
    expect(tree.productMatches(ref, 'cat_masc'), isFalse);

    final saved = _save(p, tree);
    expect(saved.pathIds, ['cat_fem', 'cat_rel', 'cat_ane']);
    final again = _reopen(p
      ..categoryId = saved.id
      ..categoryPathIds = saved.pathIds
      ..categoryPathNames = saved.pathNames);
    expect(again.categoryId, 'cat_ane', reason: 'vínculo não se perde na reabertura');
    expect(
        ProductCategoryFields.pathAgreesWithText(again.categoryPathNames, again.categoria, again.subcategoria),
        isTrue);
    expect(tree.node(again.categoryId)!.pathNames, ['Feminino', 'Religiosos', 'Anéis']);
  });

  test('rename de nível 3+: o salvamento passa a gravar os nomes atuais', () {
    final tree0 = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
    final p = _filed(tree0.node('cat_ns')!);
    final tree = CategoryTree.build(lojaId: 'mirjoias', docs: _renamed('cat_ane', 'Anel', 'Anéis'));
    final saved = _save(p, tree);
    expect(saved.pathNames, ['Feminino', 'Religioso', 'Anel', 'Nossa Senhora']);
    expect(saved.pathIds, ['cat_fem', 'cat_rel', 'cat_ane', 'cat_ns']);
  });

  test('categoria arquivada ou texto alterado: nunca grava caminho incoerente', () {
    final tree0 = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
    final p = _filed(tree0.node('cat_ane')!);
    p.categoria = 'Masculino';
    expect(_save(p, tree0).id, '');
  });

  group('modo misto (MIXED_CATEGORY_MODE_PASS)', () {
    final hier = CategoryProductRef(
        pathIds: const ['cat_fem', 'cat_rel', 'cat_ane'], categorias: const ['Feminino'], subcategorias: const ['Religioso']);
    const legacyFem = CategoryProductRef(categorias: ['Feminino'], subcategorias: ['Religioso']);
    const legacyOnly = CategoryProductRef(categorias: ['Brincos']);
    final products = [hier, legacyFem, legacyOnly];

    test('loja só legado: categorias de texto viram nós virtuais e filtros funcionam', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: const [], products: products);
      final roots = tree.roots.map((n) => n.nome).toList();
      expect(roots, containsAll(['Feminino', 'Brincos']));
      final fem = tree.roots.firstWhere((n) => n.nome == 'Feminino');
      expect(fem.isVirtual, isTrue);
      expect(products.where((r) => tree.productMatches(r, fem.id)).length, 2);
      final brincos = tree.roots.firstWhere((n) => n.nome == 'Brincos');
      expect(tree.productMatches(legacyOnly, brincos.id), isTrue);
    });

    test('loja com árvore + legado: pai inclui ambos, cada produto uma vez, Masculino fora', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels(), products: products);
      final inFem = products.where((r) => tree.productMatches(r, 'cat_fem')).toList();
      expect(inFem.length, 2);
      expect(inFem.toSet().length, inFem.length, reason: 'PRODUCT_DUPLICATION_COUNT=0');
      expect(products.where((r) => tree.productMatches(r, 'cat_rel')).length, 2);
      expect(products.where((r) => tree.productMatches(r, 'cat_ane')).toList(), [hier]);
      expect(products.where((r) => tree.productMatches(r, 'cat_masc')), isEmpty);
      final brincos = tree.roots.firstWhere((n) => n.nome == 'Brincos');
      expect(brincos.isVirtual, isTrue, reason: 'legado continua visível');
      expect(tree.productMatches(legacyOnly, brincos.id), isTrue);
      expect(tree.roots.where((n) => normalizeCategoryName(n.nome) == 'feminino').length, 1);
    });

    test('Masculino > Religioso coexiste com Feminino > Religioso sem misturar produtos', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        ...sixLevels(),
        doc('cat_mrel', 'Religioso', parentId: 'cat_masc'),
      ], products: products);
      expect(tree.node('cat_mrel')!.pathNames, ['Masculino', 'Religioso']);
      expect(tree.productMatches(hier, 'cat_mrel'), isFalse);
      expect(tree.productMatches(legacyFem, 'cat_mrel'), isFalse);
    });
  });
}
