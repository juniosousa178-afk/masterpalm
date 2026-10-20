import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/features/categories/category_tree.dart';

Map<String, dynamic> doc(
  String id,
  String nome, {
  String? parentId,
  String lojaId = 'mirjoias',
  bool deleted = false,
  int? sortOrder,
  List<String> legacyNames = const [],
}) =>
    {
      'id': id,
      'lojaId': lojaId,
      'nome': nome,
      'parentId': parentId,
      'isDeleted': deleted,
      if (sortOrder != null) 'sortOrder': sortOrder,
      'legacyNames': legacyNames,
    };

/// Feminino > Religioso > Anéis > Nossa Senhora > Prata 925 > Cravejados; Masculino separado.
List<Map<String, dynamic>> sixLevels({String lojaId = 'mirjoias', String p = 'cat_'}) => [
      doc('${p}fem', 'Feminino', lojaId: lojaId),
      doc('${p}rel', 'Religioso', parentId: '${p}fem', lojaId: lojaId),
      doc('${p}ane', 'Anéis', parentId: '${p}rel', lojaId: lojaId),
      doc('${p}ns', 'Nossa Senhora', parentId: '${p}ane', lojaId: lojaId),
      doc('${p}p925', 'Prata 925', parentId: '${p}ns', lojaId: lojaId),
      doc('${p}crav', 'Cravejados', parentId: '${p}p925', lojaId: lojaId),
      doc('${p}masc', 'Masculino', lojaId: lojaId),
    ];

void main() {
  group('estrutura', () {
    test('N1..N6 montados pela cadeia de parentId (CATEGORY_DEPTH_6_ALLOWED)', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
      final leaf = tree.node('cat_crav')!;
      expect(leaf.depth, 6);
      expect(leaf.pathIds, ['cat_fem', 'cat_rel', 'cat_ane', 'cat_ns', 'cat_p925', 'cat_crav']);
      expect(leaf.breadcrumb, 'Feminino > Religioso > Anéis > Nossa Senhora > Prata 925 > Cravejados');
      expect(tree.validateNewChild(tree.node('cat_p925')), isNull);
      expect(tree.quarantined, isEmpty);
    });

    test('filho de N6 bloqueado com mensagem clara (CATEGORY_DEPTH_7_BLOCKED)', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
      final n6 = tree.node('cat_crav')!;
      expect(n6.canAddChild, isFalse);
      expect(tree.validateNewChild(n6), kCategoryDepthLimitMessage);
      expect(kCategoryDepthLimitMessage, 'Você pode criar categorias em até 6 níveis.');
    });

    test('documento no nível 7 fica em quarentena', () {
      final docs = [...sixLevels(), doc('cat_n7', 'Sétimo', parentId: 'cat_crav')];
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs);
      expect(tree.node('cat_n7'), isNull);
      expect(tree.quarantined['cat_n7'], 'DEPTH_LIMIT');
    });

    test('ciclos e auto-pai em quarentena; mover para descendente bloqueado (CATEGORY_CYCLE_BLOCKED)', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        ...sixLevels(),
        doc('cat_a', 'A', parentId: 'cat_b'),
        doc('cat_b', 'B', parentId: 'cat_a'),
        doc('cat_self', 'Self', parentId: 'cat_self'),
      ]);
      expect(tree.node('cat_a'), isNull);
      expect(tree.node('cat_b'), isNull);
      expect(tree.node('cat_self'), isNull);
      expect(tree.quarantined['cat_a'], 'CYCLE');
      expect(tree.quarantined['cat_self'], 'CYCLE');
      expect(tree.validateMove('cat_fem', 'cat_fem'), kCategoryCycleSelfMessage);
      expect(tree.validateMove('cat_fem', 'cat_ane'), kCategoryCycleDescendantMessage);
      expect(tree.validateMove('cat_rel', 'cat_masc'), isNull);
      expect(tree.validateMove('cat_ane', 'cat_crav'), isNotNull);
    });

    test('mover subárvore que estoura 6 níveis é bloqueado', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        ...sixLevels(),
        doc('cat_m2', 'Correntes', parentId: 'cat_masc'),
      ]);
      expect(tree.validateMove('cat_rel', 'cat_m2'), kCategoryDepthLimitMessage);
    });

    test('pai de outra loja é ignorado (CATEGORY_CROSS_TENANT_BLOCKED)', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        doc('cat_x', 'Intrusa', lojaId: 'nathy-pratas-e-folheados'),
        doc('cat_child', 'Filha', parentId: 'cat_x'),
      ]);
      expect(tree.node('cat_x'), isNull);
      expect(tree.node('cat_child'), isNull);
      expect(tree.quarantined['cat_x'], 'CROSS_TENANT');
      expect(tree.quarantined['cat_child'], 'CROSS_TENANT');
    });

    test('árvores idênticas em duas lojas não se cruzam (CATEGORY_TENANT_ISOLATION)', () {
      final mir = sixLevels(lojaId: 'mirjoias', p: 'cat_m_');
      final nathy = sixLevels(lojaId: 'nathy-pratas-e-folheados', p: 'cat_n_');
      final treeMir = CategoryTree.build(lojaId: 'mirjoias', docs: [...mir, ...nathy]);
      final treeNathy =
          CategoryTree.build(lojaId: 'nathy-pratas-e-folheados', docs: [...mir, ...nathy]);
      expect(treeMir.activeNodes.every((n) => n.lojaId == 'mirjoias'), isTrue);
      expect(treeNathy.activeNodes.every((n) => n.lojaId == 'nathy-pratas-e-folheados'), isTrue);
      expect(treeMir.node('cat_n_fem'), isNull);
      expect(treeNathy.node('cat_m_fem'), isNull);
      expect(treeMir.activeNodes.length, 7);
      expect(treeNathy.activeNodes.length, 7);
    });

    test('ordem: sortOrder e depois nome', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        doc('cat_b', 'Brincos', sortOrder: 1),
        doc('cat_a', 'Anéis', sortOrder: 0),
        doc('cat_c', 'Colares'),
      ]);
      expect(tree.roots.map((n) => n.nome), ['Anéis', 'Brincos', 'Colares']);
    });

    test('carregar a árvore inteira é uma montagem em memória (CATEGORY_TREE_N_PLUS_ONE=false)', () {
      final docs = <Map<String, dynamic>>[];
      for (var r = 0; r < 20; r++) {
        docs.add(doc('cat_r$r', 'Raiz $r'));
        var parent = 'cat_r$r';
        for (var d = 2; d <= 6; d++) {
          final id = 'cat_r${r}_$d';
          docs.add(doc(id, 'N$d', parentId: parent));
          parent = id;
        }
      }
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs);
      expect(tree.activeNodes.length, 120);
      expect(tree.node('cat_r19_6')!.depth, 6);
    });
  });

  group('produtos', () {
    final docs = sixLevels();
    const anelNS = CategoryProductRef(
      pathIds: ['cat_fem', 'cat_rel', 'cat_ane'],
      categorias: ['Feminino'],
      subcategorias: ['Religioso'],
    );

    test('Anel Nossa Senhora aparece em Feminino, Religioso e Anéis; não em Masculino (PARENT_CATEGORY_INCLUDES_DESCENDANT_PRODUCTS)', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs, products: const [anelNS]);
      expect(tree.productMatches(anelNS, 'cat_fem'), isTrue);
      expect(tree.productMatches(anelNS, 'cat_rel'), isTrue);
      expect(tree.productMatches(anelNS, 'cat_ane'), isTrue);
      expect(tree.productMatches(anelNS, 'cat_masc'), isFalse);
      expect(tree.productMatches(anelNS, 'cat_ns'), isFalse);
      expect(tree.productCount('cat_fem'), 1);
      expect(tree.productCount('cat_masc'), 0);
      expect(tree.leafForProduct(anelNS)!.id, 'cat_ane');
    });

    test('produto em N6 aparece em todos os ancestrais', () {
      const p = CategoryProductRef(
          pathIds: ['cat_fem', 'cat_rel', 'cat_ane', 'cat_ns', 'cat_p925', 'cat_crav']);
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs, products: const [p]);
      for (final id in ['cat_fem', 'cat_rel', 'cat_ane', 'cat_ns', 'cat_p925', 'cat_crav']) {
        expect(tree.productMatches(p, id), isTrue, reason: id);
      }
      expect(tree.productMatches(p, 'cat_masc'), isFalse);
    });

    test('produto conta uma vez por nó (sem duplicar na listagem)', () {
      const p = CategoryProductRef(
        pathIds: ['cat_fem', 'cat_rel', 'cat_ane'],
        categorias: ['Feminino', 'feminino'],
        subcategorias: ['Religioso', 'religioso'],
      );
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs, products: const [p]);
      expect(tree.productCount('cat_fem'), 1);
      expect(tree.productCount('cat_rel'), 1);
    });

    test('documento do catálogo: trio + texto; rótulo "Combo" de combo não vira categoria', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs);
      final anel = CategoryProductRef.fromMap({
        'categoria': 'Feminino',
        'subcategoria': 'Religioso',
        'categoryId': 'cat_ane',
        'categoryPathIds': ['cat_fem', 'cat_rel', 'cat_ane'],
        'categoryPathNames': ['Feminino', 'Religioso', 'Anéis'],
      }, skipComboLabel: true);
      expect(tree.productMatches(anel, 'cat_ane'), isTrue);
      expect(tree.productMatches(anel, 'cat_masc'), isFalse);
      final combo = CategoryProductRef.fromMap(
          {'tipoProduto': 'combo', 'categoria': 'Combo', 'categoriasExtras': ['Masculino']},
          skipComboLabel: true);
      expect(combo.categorias, ['Masculino']);
      expect(tree.productMatches(combo, 'cat_masc'), isTrue);
      final antigo = CategoryProductRef.fromMap({'categoria': 'Masculino'});
      expect(antigo.pathIds, isEmpty);
      expect(tree.productMatches(antigo, 'cat_masc'), isTrue);
    });

    test('caminho de outra loja não vale nesta loja', () {
      const p = CategoryProductRef(pathIds: ['cat_n_fem', 'cat_n_rel']);
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: docs, products: const [p]);
      expect(tree.idsForProduct(p), isEmpty);
    });

    test('categoria arquivada deixa de valer; texto legado continua', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        doc('cat_fem', 'Feminino'),
        doc('cat_old', 'Antiga', parentId: 'cat_fem', deleted: true),
      ]);
      const p = CategoryProductRef(pathIds: ['cat_fem', 'cat_old'], categorias: ['Feminino']);
      expect(tree.idsForProduct(p), {'cat_fem'});
      expect(tree.childrenOf('cat_fem'), isEmpty);
    });
  });

  group('migração compatível (EXISTING_CATEGORY_MIGRATION_SAFE)', () {
    test('categoria/subcategoria de texto viram nós virtuais 1–2 sem escrita', () {
      const legacy = CategoryProductRef(categorias: ['Anéis'], subcategorias: ['Prata']);
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: const [], products: const [legacy]);
      final root = tree.roots.single;
      expect(root.isVirtual, isTrue);
      expect(root.depth, 1);
      expect(root.parentId, isNull);
      expect(root.pathNames, ['Anéis']);
      final sub = tree.childrenOf(root.id).single;
      expect(sub.depth, 2);
      expect(sub.pathIds, [root.id, sub.id]);
      expect(sub.toRef(), {'legacyPath': ['Anéis', 'Prata']});
      expect(tree.productMatches(legacy, root.id), isTrue);
      expect(tree.productMatches(legacy, sub.id), isTrue);
    });

    test('texto legado casa com a categoria cadastrada (acento/maiúscula), sem duplicar', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [doc('cat_ane', 'Anéis')], products: const [
        CategoryProductRef(categorias: ['aneis']),
        CategoryProductRef(categorias: ['ANÉIS']),
      ]);
      expect(tree.roots, hasLength(1));
      expect(tree.roots.single.id, 'cat_ane');
      expect(tree.productCount('cat_ane'), 2);
    });

    test('nome antigo (renomeado) continua resolvendo; nome atual tem prioridade', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: [
        doc('cat_ane', 'Anéis', legacyNames: const ['Aneis de prata']),
        doc('cat_prata', 'Aneis de prata'),
      ]);
      expect(tree.activeChildByName(null, 'Aneis de prata')!.id, 'cat_prata');
      final only = CategoryTree.build(lojaId: 'mirjoias', docs: [
        doc('cat_ane', 'Anéis', legacyNames: const ['Aneis de prata']),
      ]);
      const p = CategoryProductRef(categorias: ['Aneis de prata']);
      expect(only.productMatches(p, 'cat_ane'), isTrue);
    });

    test('virtual não pode ser arquivado; nó com filhos ou produtos também não', () {
      final tree = CategoryTree.build(
        lojaId: 'mirjoias',
        docs: sixLevels(),
        products: const [CategoryProductRef(categorias: ['Brincos'])],
      );
      final brincos = tree.roots.firstWhere((n) => n.nome == 'Brincos');
      expect(tree.archiveBlocker(brincos), kCategoryHasProductsMessage);
      expect(tree.archiveBlocker(tree.node('cat_fem')!), kCategoryHasChildrenMessage);
      expect(kCategoryHasChildrenMessage, 'Esta categoria possui subcategorias.');
      expect(tree.archiveBlocker(tree.node('cat_masc')!), isNull);
    });

    test('produto em categoria impede excluir (CATEGORY_WITH_PRODUCTS_DELETE_BLOCKED)', () {
      final tree = CategoryTree.build(
        lojaId: 'mirjoias',
        docs: sixLevels(),
        products: const [CategoryProductRef(pathIds: ['cat_masc'])],
      );
      expect(tree.archiveBlocker(tree.node('cat_masc')!), kCategoryHasProductsMessage);
    });
  });

  group('busca', () {
    test('"anel" encontra Feminino > Religioso > Anéis com caminho completo', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
      final results = tree.search('anel');
      expect(results.map((n) => n.id), contains('cat_ane'));
      expect(results.firstWhere((n) => n.id == 'cat_ane').breadcrumb,
          'Feminino > Religioso > Anéis');
    });

    test('busca ignora acento e caixa; termo inexistente vazio', () {
      final tree = CategoryTree.build(lojaId: 'mirjoias', docs: sixLevels());
      expect(tree.search('NOSSA senhora').single.id, 'cat_ns');
      expect(tree.search('prata 925').single.id, 'cat_p925');
      expect(tree.search('relogio'), isEmpty);
      expect(tree.search('  '), isEmpty);
    });
  });

  test('normalização de nomes', () {
    expect(normalizeCategoryName('  Anéis   de  Prata '), 'aneis de prata');
    expect(cleanCategoryName('  Anéis   de  Prata '), 'Anéis de Prata');
  });
}
