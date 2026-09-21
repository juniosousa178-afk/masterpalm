import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_sale_variation_picker.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/venda_produto_stock_hydrate_service.dart';

Produto _p({
  required String id,
  required String nome,
  required int qty,
  Map<String, dynamic>? variacoes,
  Map<String, int>? ept,
  List<String>? tamanhos,
  String? pendingOp,
  int? pendingBase,
  int rev = 0,
}) {
  return Produto(
    nome: nome,
    custoReal: 0,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 10,
    quantidade: qty,
    precoUnitario: 10,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 1, 1),
    codigoBarras: 'X',
    idFirebase: id,
    lojaId: 'nathy-pratas-e-folheados',
    stockRevision: rev,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingBase,
    variacoes: variacoes,
    estoquePorTamanho: ept ?? const {},
    tamanhos: tamanhos ?? const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeSemCorAliasCells', () {
    test('aliases sem-cor with specific colors do not double-count', () {
      final raw = {
        '15|prata': 1,
        '15|sem-cor': 1,
        '17|prata': 1,
        '17|sem-cor': 1,
      };
      final norm = normalizeSemCorAliasCells(raw);
      expect(sumNormalizedCells(norm), 2);
      final opts = saleOptionsFromNormalizedCells(norm);
      expect(opts.map((e) => e.variationKey).toList(), ['15|prata', '17|prata']);
    });

    test('sem-cor alone remains valid', () {
      final norm = normalizeSemCorAliasCells({'15|sem-cor': 1});
      expect(sumNormalizedCells(norm), 1);
      expect(saleOptionsFromNormalizedCells(norm).single.tamanho, '15');
    });

    test('sem-cor projection dropped when specific colors exist', () {
      final norm = normalizeSemCorAliasCells({
        '15|prata': 1,
        '15|azul': 1,
        '15|sem-cor': 2,
      });
      expect(sumNormalizedCells(norm), 2);
      expect(norm.keys.toSet(), {'15|prata', '15|azul'});
    });
  });

  group('effectiveStockKindFromRemote', () {
    test('explicit variation', () {
      expect(
        effectiveStockKindFromRemote({
          'stockKind': 'variation',
          'variacoes': {
            '15': {'sem-cor': 1},
          },
        }),
        EffectiveStockKind.variation,
      );
    });

    test('legacy null stockKind with canonical cells → variation', () {
      expect(
        effectiveStockKindFromRemote({
          'quantidade': 2,
          'variacoes': {
            '15': {'verde': 1},
            '16': {'verde': 1},
          },
        }),
        EffectiveStockKind.variation,
      );
    });

    test('tamanhos alone without cells → simple', () {
      expect(
        effectiveStockKindFromRemote({
          'stockKind': 'simple',
          'tamanhos': ['15', '22'],
          'quantidade': 2,
        }),
        EffectiveStockKind.simple,
      );
    });
  });

  group('Anel Lacinho canary hydration', () {
    late FakeFirebaseFirestore fs;

    setUp(() {
      fs = FakeFirebaseFirestore();
      VendaProdutoStockHydrateService.resetForTests();
      VendaProdutoStockHydrateService.debugFirestoreOverride = fs;
    });

    tearDown(() {
      VendaProdutoStockHydrateService.resetForTests();
    });

    test('stale Hive simple hydrates to variation picker options 15/22', () async {
      const id = 'nathy-pratas-e-folheados-anel-lacinho-encanto';
      final local = _p(
        id: id,
        nome: 'Anel Lacinho Encanto',
        qty: 2,
        rev: 8,
        tamanhos: ['15', '22'],
      );
      expect(local.usaVariacoes, isFalse);
      expect(produtoHasVariationIdentities(local), isFalse);
      expect(
        VendaProdutoStockHydrateService.requiresVariationPicker(local),
        isFalse,
      );
      expect(
        produtoSaleVariationPickerOptions(local)
            .any((o) => o.tamanho == '15' || o.tamanho == '22'),
        isFalse,
      );

      await fs
          .collection('lojas')
          .doc('nathy-pratas-e-folheados')
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({
        'quantidade': 2,
        'stockKind': 'variation',
        'stockRevision': 8,
        'stockOperationId': 'op-lacinho',
        'variacoes': {
          '15': {'sem-cor': 1},
          '22': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'15': 1, '22': 1},
      });

      final ok = await VendaProdutoStockHydrateService.hydrateProdutoFromRemoteEstoque(
        lojaId: 'nathy-pratas-e-folheados',
        produto: local,
      );
      expect(ok, isTrue);
      expect(effectiveStockKindFromProduto(local), EffectiveStockKind.variation);
      expect(local.quantidade, 2);
      expect(VendaProdutoStockHydrateService.requiresVariationPicker(local), isTrue);

      final opts = produtoSaleVariationPickerOptions(local);
      expect(opts.map((e) => e.variationKey).toList(), ['15|sem-cor', '22|sem-cor']);
      expect(opts.map((e) => e.label).toList(), ['15 (1)', '22 (1)']);
    });

    test('pending blocks overwrite', () async {
      const id = 'nathy-pending-block';
      final local = _p(
        id: id,
        nome: 'Pending',
        qty: 1,
        pendingOp: 'pend-1',
        pendingBase: 1,
        variacoes: {
          '21': {'sem-cor': 1},
        },
        ept: {'21': 1},
      );
      await fs
          .collection('lojas')
          .doc('nathy-pratas-e-folheados')
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({
        'quantidade': 3,
        'stockKind': 'variation',
        'stockRevision': 9,
        'variacoes': {
          '14': {'sem-cor': 1},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
      });

      final ok = await VendaProdutoStockHydrateService.hydrateProdutoFromRemoteEstoque(
        lojaId: 'nathy-pratas-e-folheados',
        produto: local,
      );
      expect(ok, isFalse);
      expect(hasPendingStockMutation(local), isTrue);
      expect(local.quantidade, 1);
      expect(produtoSaleVariationPickerOptions(local).single.tamanho, '21');
    });
  });

  group('Anel Ondinha cache stale', () {
    late FakeFirebaseFirestore fs;

    setUp(() {
      fs = FakeFirebaseFirestore();
      VendaProdutoStockHydrateService.resetForTests();
      VendaProdutoStockHydrateService.debugFirestoreOverride = fs;
    });

    tearDown(VendaProdutoStockHydrateService.resetForTests);

    test('local qty=1 remote qty=3 hydrates sale options 14/18/21', () async {
      const id = 'nathy-pratas-e-folheados-anel-ondinha';
      final local = _p(
        id: id,
        nome: 'Anel Ondinha',
        qty: 1,
        rev: 9,
        variacoes: {
          '21': {'sem-cor': 1},
        },
        ept: {'21': 1},
        tamanhos: ['14', '18', '21'],
      );

      await fs
          .collection('lojas')
          .doc('nathy-pratas-e-folheados')
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set({
        'quantidade': 3,
        'stockKind': 'variation',
        'stockRevision': 9,
        'variacoes': {
          '14': {'sem-cor': 1},
          '15': {'sem-cor': 0},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'14': 1, '15': 0, '18': 1, '21': 1},
      });

      await VendaProdutoStockHydrateService.hydrateProdutoFromRemoteEstoque(
        lojaId: 'nathy-pratas-e-folheados',
        produto: local,
      );
      expect(local.quantidade, 3);
      final keys =
          produtoSaleVariationPickerOptions(local).map((e) => e.tamanho).toList();
      expect(keys, ['14', '18', '21']);
    });
  });

  group('applyAuthoritativeRemoteStockToProduto', () {
    test('does not write remote — only mutates local fields', () {
      final local = _p(
        id: 'x',
        nome: 'X',
        qty: 1,
        tamanhos: ['15', '22'],
      );
      applyAuthoritativeRemoteStockToProduto(
        local,
        remote: {
          'quantidade': 2,
          'stockKind': 'variation',
          'stockRevision': 8,
          'stockOperationId': 'op',
          'variacoes': {
            '15': {'sem-cor': 1},
            '22': {'sem-cor': 1},
          },
        },
      );
      expect(local.quantidade, 2);
      expect(local.usaVariacoes, isTrue);
      expect(captureLocalStockSnapshot(local)['LOCAL_QTY'], 2);
    });
  });

  group('6 stale SALE_VARIATION_MISSING cases hydrate to remote options', () {
    late FakeFirebaseFirestore fs;

    setUp(() {
      fs = FakeFirebaseFirestore();
      VendaProdutoStockHydrateService.resetForTests();
      VendaProdutoStockHydrateService.debugFirestoreOverride = fs;
    });

    tearDown(VendaProdutoStockHydrateService.resetForTests);

    Future<void> seedAndHydrate({
      required String id,
      required String nome,
      required int localQty,
      required Map<String, dynamic>? localVars,
      required Map<String, int> localEpt,
      required List<String> localTamanhos,
      required Map<String, dynamic> remote,
      required List<String> expectedKeys,
    }) async {
      final local = _p(
        id: id,
        nome: nome,
        qty: localQty,
        variacoes: localVars,
        ept: localEpt,
        tamanhos: localTamanhos,
      );
      await fs
          .collection('lojas')
          .doc('nathy-pratas-e-folheados')
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set(remote);
      final ok = await VendaProdutoStockHydrateService.hydrateProdutoFromRemoteEstoque(
        lojaId: 'nathy-pratas-e-folheados',
        produto: local,
      );
      expect(ok, isTrue, reason: nome);
      expect(
        VendaProdutoStockHydrateService.requiresVariationPicker(local),
        isTrue,
        reason: nome,
      );
      final keys =
          produtoSaleVariationPickerOptions(local).map((e) => e.variationKey).toList()
            ..sort();
      expect(keys, expectedKeys..sort(), reason: nome);
    }

    test('all 6 recover sale options from remote', () async {
      await seedAndHydrate(
        id: 'nathy-pratas-e-folheados-anel-lacinho-encanto',
        nome: 'Anel Lacinho Encanto',
        localQty: 2,
        localVars: null,
        localEpt: const {},
        localTamanhos: const ['15', '22'],
        remote: {
          'quantidade': 2,
          'stockKind': 'variation',
          'variacoes': {
            '15': {'sem-cor': 1},
            '22': {'sem-cor': 1},
          },
        },
        expectedKeys: ['15|sem-cor', '22|sem-cor'],
      );
      await seedAndHydrate(
        id: 'nathy-pratas-e-folheados-anel-f',
        nome: 'Anel Fé',
        localQty: 4,
        localVars: null,
        localEpt: const {'16': 1},
        localTamanhos: const ['16', '17', '18', '22'],
        remote: {
          'quantidade': 4,
          'stockKind': 'variation',
          'variacoes': {
            '16': {'sem-cor': 1},
            '17': {'sem-cor': 1},
            '18': {'sem-cor': 1},
            '22': {'sem-cor': 1},
          },
        },
        expectedKeys: [
          '16|sem-cor',
          '17|sem-cor',
          '18|sem-cor',
          '22|sem-cor',
        ],
      );
      await seedAndHydrate(
        id: 'nathy-pratas-e-folheados-anel-f-zirc-nias',
        nome: 'Anel Fé Zircônias',
        localQty: 5,
        localVars: null,
        localEpt: const {'16': 1, '18': 1, '23': 1},
        localTamanhos: const ['16', '17', '18', '19', '23'],
        remote: {
          'quantidade': 5,
          'stockKind': 'variation',
          'variacoes': {
            '16': {'sem-cor': 1},
            '17': {'prata': 1},
            '18': {'sem-cor': 1},
            '19': {'prata': 1},
            '23': {'sem-cor': 1},
          },
        },
        expectedKeys: [
          '16|sem-cor',
          '17|prata',
          '18|sem-cor',
          '19|prata',
          '23|sem-cor',
        ],
      );
      await seedAndHydrate(
        id: 'nathy-pratas-e-folheados-anel-solit-rio-elegante-cristal',
        nome: 'Anel Solitário Elegante Cristal',
        localQty: 1,
        localVars: null,
        localEpt: const {'14': 1},
        localTamanhos: const ['18', '14'],
        remote: {
          'quantidade': 2,
          'stockKind': 'variation',
          'variacoes': {
            '14': {'cristal': 1},
            '18': {'Cristal': 1},
          },
        },
        expectedKeys: ['14|cristal', '18|Cristal'],
      );
      await seedAndHydrate(
        id: 'nathy-pratas-e-folheados-anel-solit-rio-oval-belle',
        nome: 'Anel Solitário Oval Belle',
        localQty: 1,
        localVars: null,
        localEpt: const {'17/18': 1},
        localTamanhos: const ['17/18'],
        remote: {
          'quantidade': 1,
          'stockKind': 'variation',
          'variacoes': {
            '17/18': {'sem-cor': 1},
          },
        },
        expectedKeys: ['17/18|sem-cor'],
      );
      await seedAndHydrate(
        id: 'nathy-pratas-e-folheados-conjunto-cora-o-meigo-azul',
        nome: 'Conjunto Gota Lilás Luxo',
        localQty: 1,
        localVars: null,
        localEpt: const {'45cm': 1},
        localTamanhos: const ['45cm'],
        remote: {
          'quantidade': 1,
          'stockKind': 'variation',
          'variacoes': {
            '45cm': {'sem-cor': 1},
          },
        },
        expectedKeys: ['45cm|sem-cor'],
      );
    });
  });

  group('produtoHasVariationIdentities', () {
    test('tamanhos alone is LEGACY_SIZE_METADATA_ONLY — not variation identity', () {
      final p = _p(
        id: 'legacy',
        nome: 'Legacy',
        qty: 0,
        tamanhos: ['15', '22'],
      );
      expect(produtoHasVariationIdentities(p), isFalse);
      expect(produtoSaleVariationPickerOptions(p), isEmpty);
    });
  });
}
