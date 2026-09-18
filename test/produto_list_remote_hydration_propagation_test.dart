import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_list_remote_hydration.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';

Produto _localVar({
  required Map<String, dynamic> variacoes,
  Map<String, int> ept = const {},
  int quantidade = 0,
  int stockRevision = 0,
  String? pendingOp,
  int? pendingBase,
}) {
  final p = Produto(
    nome: 'Fixture Variable',
    custoReal: 1,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 10,
    quantidade: quantidade,
    precoUnitario: 10,
    categoria: 'Test',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: 'loja-test-a',
    idFirebase: 'loja-test-a-fixture-var',
    slug: 'loja-test-a-fixture-var',
    variacoes: variacoes,
    estoquePorTamanho: ept,
    tamanhos: ept.keys.toList(),
  )..stockRevision = stockRevision;
  if (pendingOp != null) {
    markPendingStockMutation(
      p,
      operationId: pendingOp,
      baseRevision: pendingBase,
    );
  }
  return p;
}

Map<String, dynamic> _remote({
  required Map<String, dynamic> variacoes,
  Map<String, int>? ept,
  required int quantidade,
  int stockRevision = 0,
  String? operationId,
}) {
  final out = <String, dynamic>{
    'nome': 'Fixture Variable',
    'quantidade': quantidade,
    'variacoes': variacoes,
    'estoquePorTamanho': ept ??
        {
          for (final e in variacoes.entries)
            e.key: (e.value is Map
                ? (e.value as Map).values.fold<int>(
                    0,
                    (a, v) => a + ((v as num?)?.toInt() ?? 0),
                  )
                : 0),
        },
    kProdutoStockRevisionField: stockRevision,
  };
  if (operationId != null) {
    out[kProdutoStockOperationIdField] = operationId;
  }
  return out;
}

void main() {
  group('list remote hydration propagation', () {
    test('1. stale partial Hive → complete remote accepted (list pull)', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 1},
        },
        ept: const {'21': 1},
        quantidade: 1,
        stockRevision: 0,
      );
      final remote = _remote(
        variacoes: {
          '14': {'sem-cor': 1},
          '15': {'sem-cor': 0},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        quantidade: 3,
        stockRevision: 6,
      );

      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
      expect(
        evaluatePullStockMergeByRevision(local: local, remoteData: remote),
        PullStockMergeDecision.acceptRemote,
      );
    });

    test('2. local positive → remote zero wins on list pull', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 2},
        },
        ept: const {'21': 2},
        quantidade: 2,
        stockRevision: 0,
      );
      final remote = _remote(
        variacoes: {
          '21': {'sem-cor': 0},
        },
        quantidade: 0,
        stockRevision: 0,
      );

      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
    });

    test('3. local zero → remote positive propagates', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 0},
        },
        ept: const {'21': 0},
        quantidade: 0,
        stockRevision: 0,
      );
      final remote = _remote(
        variacoes: {
          '21': {'sem-cor': 4},
        },
        quantidade: 4,
        stockRevision: 2,
      );

      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
      expect(
        evaluatePullStockMergeByRevision(local: local, remoteData: remote),
        PullStockMergeDecision.acceptRemote,
      );
    });

    test('4. local missing rows → remote complete set more-complete', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 1},
        },
        ept: const {'21': 1},
        quantidade: 1,
      );
      final remote = _remote(
        variacoes: {
          '14': {'sem-cor': 1},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        quantidade: 3,
        stockRevision: 0,
      );
      final localG = ProdutoEstoqueGradeSnapshot.fromProduto(local);
      final remoteG = ProdutoEstoqueGradeSnapshot.fromRemote(remote);
      expect(remoteG.isStrictlyMoreCompleteThan(localG), isTrue);
      expect(
        evaluatePullStockMergeByRevision(local: local, remoteData: remote),
        PullStockMergeDecision.acceptRemote,
      );
    });

    test('5. remote failure path: preserve helper does not force accept', () {
      // Network failure is handled by caller not invoking pull; when local
      // revision is newer than remote, list pull still preserves local.
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 5},
        },
        ept: const {'21': 5},
        quantidade: 5,
        stockRevision: 9,
      );
      final remote = _remote(
        variacoes: {
          '21': {'sem-cor': 1},
        },
        quantidade: 1,
        stockRevision: 3,
      );
      expect(
        shouldAcceptRemoteGradeOnAuthoritativeListPull(
          local: local,
          remoteData: remote,
        ),
        isFalse,
      );
      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isTrue,
      );
    });

    test('6. delayed previous-store box name must not match current store', () {
      expect(
        listPullBoxMatchesStoreConvention(
          lojaId: 'loja-test-b',
          produtosBoxName: HiveBoxNames.produtos('loja-test-a'),
        ),
        isFalse,
      );
      expect(
        listPullBoxMatchesStoreConvention(
          lojaId: 'loja-test-b',
          produtosBoxName: HiveBoxNames.produtos('loja-test-b'),
        ),
        isTrue,
      );
      expect(
        listPullTargetStillValid(
          produtosBoxIsOpen: true,
          produtosBoxName: 'produtos_loja-test-a',
          boxNameAtSyncStart: 'produtos_loja-test-a',
        ),
        isTrue,
      );
      expect(
        listPullTargetStillValid(
          produtosBoxIsOpen: true,
          produtosBoxName: 'produtos_loja-test-b',
          boxNameAtSyncStart: 'produtos_loja-test-a',
        ),
        isFalse,
      );
    });

    test('7. same product repeated remote completion → still accept once', () {
      final local = _localVar(
        variacoes: {
          '14': {'sem-cor': 1},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        ept: const {'14': 1, '18': 1, '21': 1},
        quantidade: 3,
        stockRevision: 6,
      );
      final remote = _remote(
        variacoes: {
          '14': {'sem-cor': 1},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        quantidade: 3,
        stockRevision: 6,
      );
      expect(
        evaluatePullStockMergeByRevision(local: local, remoteData: remote),
        PullStockMergeDecision.acceptRemote,
      );
      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
    });

    test('8. stale async older revision cannot win', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 3},
        },
        ept: const {'21': 3},
        quantidade: 3,
        stockRevision: 8,
      );
      final staleRemote = _remote(
        variacoes: {
          '21': {'sem-cor': 1},
        },
        quantidade: 1,
        stockRevision: 4,
      );
      expect(
        shouldAcceptRemoteGradeOnAuthoritativeListPull(
          local: local,
          remoteData: staleRemote,
        ),
        isFalse,
      );
    });

    test('9. editor open not required — list pull accepts incomplete local', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 1},
        },
        ept: const {'21': 1},
        quantidade: 1,
      );
      final remote = _remote(
        variacoes: {
          '14': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        quantidade: 2,
        stockRevision: 1,
      );
      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
    });

    test('10. Save not required — preferRemoteQuantity path accepts', () {
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 0},
        },
        ept: const {'21': 1},
        quantidade: 1,
      );
      final remote = _remote(
        variacoes: {
          '14': {'sem-cor': 1},
          '18': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        quantidade: 3,
        stockRevision: 6,
      );
      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
    });

    test('11. list hydration does not synthesize from EPT alone', () {
      // Remote variacoes authoritative zeros; ept projection ignored for authority.
      final local = _localVar(
        variacoes: {
          '21': {'sem-cor': 0},
        },
        ept: const {'21': 9},
        quantidade: 0,
      );
      final remote = _remote(
        variacoes: {
          '21': {'sem-cor': 0},
        },
        ept: const {'21': 0},
        quantidade: 0,
        stockRevision: 2,
      );
      expect(
        shouldPreserveLocalGradeOnListPull(
          local: local,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
      final remoteG = ProdutoEstoqueGradeSnapshot.fromRemote(remote);
      expect(remoteG.cells['21|sem-cor'] ?? remoteG.cells.values.first, 0);
    });

    test('12. simple product grade empty — list pull target guard only', () {
      final simple = Produto(
        nome: 'Fixture Simple',
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 4,
        precoUnitario: 10,
        categoria: 'Test',
        dataEntrada: DateTime(2026, 1, 1),
        lojaId: 'loja-test-a',
        idFirebase: 'loja-test-a-fixture-simple',
        slug: 'loja-test-a-fixture-simple',
      )..stockRevision = 1;
      final remote = {
        'nome': 'Fixture Simple',
        'quantidade': 4,
        'variacoes': <String, dynamic>{},
        'estoquePorTamanho': <String, int>{},
        kProdutoStockRevisionField: 1,
      };
      expect(
        shouldPreserveLocalGradeOnListPull(
          local: simple,
          remoteData: remote,
          preferRemoteQuantity: true,
        ),
        isFalse,
      );
    });

    test('pending conflict still blocks list pull accept', () {
      final local = _localVar(
        variacoes: {
          'A': {'sem-cor': 4},
          'B': {'sem-cor': 4},
        },
        ept: const {'A': 4, 'B': 4},
        quantidade: 8,
        stockRevision: 5,
        pendingOp: 'op-local',
        pendingBase: 5,
      );
      final remote = _remote(
        variacoes: {
          'A': {'sem-cor': 3},
          'B': {'sem-cor': 3},
        },
        quantidade: 6,
        stockRevision: 6,
        operationId: 'op-other',
      );
      expect(
        shouldAcceptRemoteGradeOnAuthoritativeListPull(
          local: local,
          remoteData: remote,
        ),
        isFalse,
      );
    });
  });
}
