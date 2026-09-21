// Incidente Nathy: Hive stale simple → remote variation; rota de venda
// deve abrir picker (nunca simple qty sheet). Fail-closed sem opções.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_sale_variation_picker.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_produto_stock_hydrate_service.dart';

Produto _staleSimple({
  required String id,
  required String nome,
  List<String> tamanhos = const ['15', '22'],
  int qty = 2,
  String? pendingOp,
}) {
  return Produto(
    nome: nome,
    custoReal: 0,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 52.9,
    quantidade: qty,
    precoUnitario: 52.9,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 1, 1),
    codigoBarras: '',
    idFirebase: id,
    lojaId: 'nathy-pratas-e-folheados',
    stockRevision: 8,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingOp == null ? null : 8,
    tamanhos: tamanhos,
  );
}

Map<String, dynamic> _remoteVariation15_22() => {
      'quantidade': 2,
      'stockKind': 'variation',
      'stockRevision': 8,
      'stockOperationId': 'op-remote',
      'variacoes': {
        '15': {'sem-cor': 1},
        '22': {'sem-cor': 1},
      },
      'estoquePorTamanho': {'15': 1, '22': 1},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fs;

  setUp(() {
    fs = FakeFirebaseFirestore();
    VendaProdutoStockHydrateService.resetForTests();
    VendaProdutoStockHydrateService.debugFirestoreOverride = fs;
  });

  tearDown(VendaProdutoStockHydrateService.resetForTests);

  Future<void> seed(String id, [Map<String, dynamic>? data]) async {
    await fs
        .collection('lojas')
        .doc('nathy-pratas-e-folheados')
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .set(data ?? _remoteVariation15_22());
  }

  group('sale variation routing — UI decision', () {
    final cases = <String, String>{
      'Anel Lacinho Encanto':
          'nathy-pratas-e-folheados-anel-lacinho-encanto',
      'Anel Fé': 'nathy-pratas-e-folheados-anel-fe',
      'Anel Fé Zircônias': 'nathy-pratas-e-folheados-anel-fe-zirconias',
      'Anel Solitário Elegante Cristal':
          'nathy-pratas-e-folheados-anel-solitario-elegante-cristal',
      'Anel Solitário Oval Belle':
          'nathy-pratas-e-folheados-anel-solitario-oval-belle',
      'Conjunto Gota Lilás Luxo':
          'nathy-pratas-e-folheados-conjunto-gota-lilas-luxo',
    };

    for (final e in cases.entries) {
      test('${e.key}: stale simple → openVariationPicker 15/22', () async {
        await seed(e.value);
        final local = _staleSimple(id: e.value, nome: e.key);
        expect(produtoHasVariationIdentities(local), isFalse);

        final route =
            await VendaProdutoStockHydrateService.resolveSaleVariationRoute(
          lojaId: 'nathy-pratas-e-folheados',
          produto: local,
        );

        expect(route.decision, SaleVariationRouteDecision.openVariationPicker);
        expect(route.effectiveKindWire, 'variation');
        expect(
          route.options.map((o) => o.variationKey).toList(),
          ['15|sem-cor', '22|sem-cor'],
        );
        // VARIABLE_PRODUCT_CANNOT_USE_SIMPLE_QTY_SHEET
        expect(route.decision, isNot(SaleVariationRouteDecision.addAsSimple));
      });
    }

    test('Lacinho with STALE pending still opens variation picker', () async {
      const id = 'nathy-pratas-e-folheados-anel-lacinho-encanto';
      await seed(id);
      final local = _staleSimple(
        id: id,
        nome: 'Anel Lacinho Encanto',
        pendingOp: 'stale-save-op',
      );

      final route =
          await VendaProdutoStockHydrateService.resolveSaleVariationRoute(
        lojaId: 'nathy-pratas-e-folheados',
        produto: local,
      );
      expect(route.decision, SaleVariationRouteDecision.openVariationPicker);
      expect(route.options.map((o) => o.label).toList(), ['15 (1)', '22 (1)']);
    });
  });

  group('catalog save — preserve remote grade does not imply local CAS', () {
    test('empty local push preserves remote and skips grade mutate intent', () {
      final local = _staleSimple(
        id: 'nathy-pratas-e-folheados-anel-lacinho-encanto',
        nome: 'Anel Lacinho Encanto',
      );
      final remote = _remoteVariation15_22();
      expect(
        ProdutosFirestoreService.shouldPreserveRemoteGradeOnEmptyLocalPush(
          local: local,
          existingData: remote,
          variacoesPush: {},
          variacoesExtraPush: {},
          estoquePorTamPush: {},
        ),
        isTrue,
      );
      final resolved =
          ProdutosFirestoreService.resolveVariationFieldsForFirestorePush(
        local: local,
        existingData: remote,
        variacoesPush: {},
        variacoesExtraPush: {},
        estoquePorTamPush: {},
      );
      expect(resolved.rehydrateLocalFromRemote, isTrue);
      expect(resolved.variacoes.containsKey('15'), isTrue);
      expect(resolved.variacoes.containsKey('22'), isTrue);

      final effective = ProdutoEstoqueGradeSnapshot.fromRemote({
        'quantidade': remote['quantidade'],
        'variacoes': resolved.variacoes,
        'estoquePorTamanho': resolved.estoquePorTamanho,
      });
      final remoteGrade = ProdutoEstoqueGradeSnapshot.fromRemote(remote);
      expect(effective.gradeDiffersFrom(remoteGrade), isFalse);
    });
  });
}
