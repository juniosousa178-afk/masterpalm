// Nathy P0: variation picker OK, finalize fails on false stock version conflict.
// Root cause: Hive simple+stale pending (no cells) vs remote structured 15/22 —
// prep used to flush replace (or leave ambiguous) instead of structural clear.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:master_palm/core/produto_effective_stock.dart';
import 'package:master_palm/core/produto_pending_stock_reconciliation.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';
import 'package:master_palm/services/venda_produto_stock_hydrate_service.dart';

const _loja = 'nathy-pratas-e-folheados';
const _lacinhoId = 'nathy-pratas-e-folheados-anel-lacinho-encanto';

Produto _lacinhoLocalStalePending() => Produto(
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
      idFirebase: _lacinhoId,
      lojaId: _loja,
      stockRevision: 8,
      pendingStockOperationId: 'stale-editorial-pending',
      pendingStockBaseRevision: 8,
      confirmedStockOperationId: 'old-local-confirmed',
      tamanhos: const ['15', '22'],
    );

Map<String, dynamic> _lacinhoRemote() => {
      'quantidade': 2,
      'stockRevision': 8,
      'stockOperationId': 'a8f4df1a-3b8f-4412-b470-be4ee5b3d6a0',
      'stockKind': 'variation',
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
    SharedPreferences.setMockInitialValues({});
    fs = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fs;
    VendaProdutoStockHydrateService.resetForTests();
    VendaProdutoStockHydrateService.debugFirestoreOverride = fs;
    VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl = null;
  });

  tearDown(() {
    VendaProdutoStockHydrateService.resetForTests();
    ProdutosFirestoreService.debugFirestoreOverride = null;
    VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl = null;
  });

  Future<void> seedRemote([Map<String, dynamic>? data]) async {
    await fs
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_lacinhoId)
        .set(data ?? _lacinhoRemote());
  }

  group('Lacinho — false stale on finalize', () {
    test('generic pending + structured remote → STALE_STRUCTURAL clear', () {
      final local = _lacinhoLocalStalePending();
      final remote = _lacinhoRemote();
      final decision = classifyPendingAgainstRemote(local: local, remote: remote);
      expect(
        decision.classification,
        PendingStockReconcileClass.staleStructuralPending,
      );
      expect(decision.classification.mustNeverFlush, isTrue);
      expect(reconcileSafeLocalPendingAgainstRemote(local, remote: remote), isTrue);
      expect(hasPendingStockMutation(local), isFalse);
      expect(local.stockRevision, 8);
      expect(local.confirmedStockOperationId, remote['stockOperationId']);
      expect(local.estoquePorTamanho['15'], 1);
      expect(local.estoquePorTamanho['22'], 1);
    });

    test('picker then prep: pending cleared, revision refreshed, no flush', () async {
      await seedRemote();
      final local = _lacinhoLocalStalePending();
      var flushCalls = 0;
      VendaEstoqueRemotoPrepService.flushPendingStockMutationImpl =
          (lojaId, produto) async {
        flushCalls++;
        return false;
      };

      final route =
          await VendaProdutoStockHydrateService.resolveSaleVariationRoute(
        lojaId: _loja,
        produto: local,
      );
      expect(route.decision, SaleVariationRouteDecision.openVariationPicker);
      expect(
        route.options.map((o) => o.variationKey).toList(),
        ['15|sem-cor', '22|sem-cor'],
      );

      // Finalize path: Hive product still has pending (structure only in memory
      // for picker). Prep must clear without stock replace.
      final hiveProduct = _lacinhoLocalStalePending();
      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: _loja,
        produtos: [hiveProduct],
      );

      expect(hasPendingStockMutation(hiveProduct), isFalse);
      expect(hiveProduct.stockRevision, 8);
      expect(
        hiveProduct.confirmedStockOperationId,
        'a8f4df1a-3b8f-4412-b470-be4ee5b3d6a0',
      );
      expect(hiveProduct.estoquePorTamanho['15'], 1);
      expect(flushCalls, 0);
    });

    test('cell 15 and 22 available after reconcile (sale paths)', () async {
      await seedRemote();
      final local = _lacinhoLocalStalePending();
      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: _loja,
        produtos: [local],
      );
      final cells = effectiveCanonicalCellsFromRemote(_lacinhoRemote());
      expect(cells['15|sem-cor'], 1);
      expect(cells['22|sem-cor'], 1);
      expect(local.quantidade, 2);
      expect(local.stockRevision, 8);
      expect(local.estoquePorTamanho['15'], 1);
      expect(local.estoquePorTamanho['22'], 1);
    });

    test('real concurrency: remote sold 15 → prep sees insufficient cell', () async {
      await seedRemote({
        ..._lacinhoRemote(),
        'quantidade': 1,
        'stockRevision': 9,
        'stockOperationId': 'sale-other-user',
        'variacoes': {
          '15': {'sem-cor': 0},
          '22': {'sem-cor': 1},
        },
        'estoquePorTamanho': {'15': 0, '22': 1},
      });
      final local = _lacinhoLocalStalePending()
        ..pendingStockOperationId = null
        ..pendingStockBaseRevision = null
        ..stockRevision = 8
        ..quantidade = 2;

      await VendaEstoqueRemotoPrepService.refreshAuthoritativeStockCacheForSale(
        lojaId: _loja,
        produto: local,
      );
      expect(local.stockRevision, 9);
      expect(local.quantidade, 1);
      expect(local.estoquePorTamanho['15'] ?? 0, 0);
      expect(local.estoquePorTamanho['22'], 1);
      // Real CAS still required at sale command — cache refresh alone is enough
      // for UI to fail-closed on missing cell before commit.
      final options = saleOptionsFromNormalizedCells(
        normalizeSemCorAliasCells(
          Map<String, int>.from(
            local.estoquePorTamanho.map(
              (k, v) => MapEntry('$k|sem-cor', v),
            ),
          ),
        ),
      );
      expect(options.any((o) => o.tamanho == '15' && o.qty > 0), isFalse);
    });
  });

  group('six stale products — route + prep', () {
    final cases = <String, String>{
      'Anel Lacinho Encanto': _lacinhoId,
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
      test('${e.key}: picker + prep clears generic pending', () async {
        await fs
            .collection('lojas')
            .doc(_loja)
            .collection(FSPaths.estoqueProdutosCol)
            .doc(e.value)
            .set({
          ..._lacinhoRemote(),
          'nome': e.key,
        });
        final local = _lacinhoLocalStalePending()
          ..nome = e.key
          ..idFirebase = e.value;
        final route =
            await VendaProdutoStockHydrateService.resolveSaleVariationRoute(
          lojaId: _loja,
          produto: local,
        );
        expect(route.decision, SaleVariationRouteDecision.openVariationPicker);
        final prepLocal = _lacinhoLocalStalePending()
          ..nome = e.key
          ..idFirebase = e.value;
        await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: _loja,
          produtos: [prepLocal],
        );
        expect(hasPendingStockMutation(prepLocal), isFalse);
        expect(prepLocal.stockRevision, 8);
      });
    }
  });
}
