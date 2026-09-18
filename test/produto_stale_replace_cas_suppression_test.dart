import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_list_remote_hydration.dart';
import 'package:master_palm/core/produto_stale_replace_intent.dart';
import 'package:master_palm/core/produto_variation_cas_rebase.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/stock_catalog_affected_products.dart';

ProdutoStockCatalogCadastroIntent _replace({
  required int expectedRevision,
  Map<String, dynamic>? variacoes,
  int quantidade = 1,
  String nome = 'Anel',
  String operationId = 'op-1',
}) {
  return ProdutoStockCatalogCadastroIntent(
    operationId: operationId,
    kind: 'replace',
    items: [
      {'productId': 'p1', 'expectedRevision': expectedRevision},
    ],
    editorial: {'nome': nome, 'precoFinal': 10},
    definition: {
      'quantidade': quantidade,
      'variacoes': variacoes,
    },
    expectedRevision: expectedRevision,
  );
}

Map<String, dynamic> _remote({
  required int rev,
  Map<String, dynamic>? variacoes,
  int quantidade = 1,
  String nome = 'Anel',
  Map<String, int>? ept,
}) {
  return {
    'stockRevision': rev,
    'quantidade': quantidade,
    'nome': nome,
    'precoFinal': 10,
    if (variacoes != null) 'variacoes': variacoes,
    if (ept != null) 'estoquePorTamanho': ept,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stale replace CAS suppression', () {
    test('1. stale revision + no unique edit → suppressed', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 1,
          variacoes: {
            '15': {'sem-cor': 1},
          },
        ),
        remoteData: _remote(
          rev: 5,
          variacoes: {
            '15': {'sem-cor': 1},
          },
        ),
        frozenQueueIntent: true,
      );
      expect(d.dispatch, StaleReplaceDispatch.suppress);
      expect(
        d.classification,
        StaleReplaceIntentClass.alreadyReflectedRemote,
      );
    });

    test('2. stale revision + already reflected remote → suppressed', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 2,
          variacoes: {
            '15': {'sem-cor': 1},
            '18': {'sem-cor': 0},
          },
          quantidade: 1,
        ),
        remoteData: _remote(
          rev: 8,
          variacoes: {
            '15': {'sem-cor': 1},
            '18': {'sem-cor': 0},
          },
          quantidade: 1,
        ),
        frozenQueueIntent: true,
      );
      expect(d.sendsReplace, isFalse);
      expect(d.dispatch, StaleReplaceDispatch.suppress);
    });

    test('3. stale + genuine unsynced non-stock edit → editorial rebase', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 1,
          nome: 'Anel novo nome',
          variacoes: {
            '15': {'sem-cor': 1},
          },
        ),
        remoteData: _remote(
          rev: 4,
          nome: 'Anel',
          variacoes: {
            '15': {'sem-cor': 1},
          },
        ),
        frozenQueueIntent: true,
      );
      expect(
        d.classification,
        StaleReplaceIntentClass.staleWithGenuineUnsyncedEdit,
      );
      expect(d.dispatch, StaleReplaceDispatch.sendEditorialRebase);
      expect(d.sendsReplace, isFalse);
      final rebased = ProdutoStaleReplaceIntent.asEditorialRebase(
        _replace(expectedRevision: 1, nome: 'Anel novo nome'),
      );
      expect(rebased.kind, 'editorial');
      expect(rebased.definition, isNull);
    });

    test('4. stale variation-stock + concurrent remote → no blind overwrite',
        () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 1,
          variacoes: {
            '15': {'sem-cor': 0},
          },
          quantidade: 0,
        ),
        remoteData: _remote(
          rev: 6,
          variacoes: {
            '14': {'sem-cor': 1},
            '15': {'sem-cor': 1},
          },
          quantidade: 2,
        ),
        frozenQueueIntent: true,
      );
      expect(d.sendsReplace, isFalse);
      expect(d.dispatch, StaleReplaceDispatch.blockConflict);
    });

    test('5. equal revision valid replace → sent exactly once', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 4,
          variacoes: {
            '15': {'sem-cor': 2},
          },
          quantidade: 2,
        ),
        remoteData: _remote(
          rev: 4,
          variacoes: {
            '15': {'sem-cor': 1},
          },
          quantidade: 1,
        ),
      );
      expect(d.dispatch, StaleReplaceDispatch.sendReplaceOnce);
      expect(d.classification, StaleReplaceIntentClass.currentAndSendable);
    });

    test('6. newer valid local intent not falsely suppressed', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 7,
          variacoes: {
            '15': {'sem-cor': 3},
          },
          quantidade: 3,
        ),
        remoteData: _remote(
          rev: 4,
          variacoes: {
            '15': {'sem-cor': 1},
          },
        ),
      );
      expect(d.dispatch, StaleReplaceDispatch.sendReplaceOnce);
    });

    test('7. deterministic 409 → no automatic retry loop', () {
      final err = FirebaseFunctionsException(
        code: 'aborted',
        message: 'Stock revision conflict',
      );
      expect(ProdutoVariationCasRebase.isStockRevisionConflict(err), isTrue);
      expect(
        ProdutoStockCatalogCadastroSync.isRetryableTransportError(err),
        isFalse,
      );
      expect(
        ProdutoStaleReplaceIntent.isRetryableTransportError(err),
        isFalse,
      );
    });

    test('8. reconnect stale superseded intent → no replace dispatch', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 1,
          variacoes: const {},
          quantidade: 1,
        ),
        remoteData: _remote(
          rev: 9,
          variacoes: const {},
          quantidade: 1,
        ),
        frozenQueueIntent: true,
      );
      expect(d.sendsReplace, isFalse);
      expect(d.dispatch, StaleReplaceDispatch.suppress);
    });

    test('9. reconnect valid current intent → exactly one dispatch', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 3,
          variacoes: {
            'M': {'sem-cor': 2},
          },
          quantidade: 2,
        ),
        remoteData: _remote(
          rev: 3,
          variacoes: {
            'M': {'sem-cor': 1},
          },
          quantidade: 1,
        ),
        frozenQueueIntent: true,
      );
      expect(d.dispatch, StaleReplaceDispatch.sendReplaceOnce);
    });

    test('10. passive list hydration → zero replace', () {
      expect(
        ProdutoStaleReplaceIntent.passiveListHydrationEmitsReplace,
        isFalse,
      );
      final local = Produto.vazio()
        ..variacoes = {
          '21': {'sem-cor': 1},
        }
        ..quantidade = 1
        ..stockRevision = 0;
      final remote = _remote(
        rev: 6,
        variacoes: {
          '14': {'sem-cor': 1},
          '21': {'sem-cor': 1},
        },
        quantidade: 2,
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

    test('11. editor open no Save → zero replace', () {
      expect(
        ProdutoStaleReplaceIntent.editorOpenWithoutSaveEmitsReplace,
        isFalse,
      );
      final produto = Produto.vazio()
        ..idFirebase = 'p'
        ..quantidade = 1
        ..stockRevision = 2;
      expect(
        ProdutoStockCatalogCadastroSync.allowStockMutationCommand(
          forcePushFromCadastro: false,
          produto: produto,
        ),
        isFalse,
      );
    });

    test('12. no-change Save vs remote → suppress replace', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 5,
          variacoes: {
            '15': {'sem-cor': 1},
          },
          quantidade: 1,
          nome: 'Anel',
        ),
        remoteData: _remote(
          rev: 5,
          variacoes: {
            '15': {'sem-cor': 1},
          },
          quantidade: 1,
          nome: 'Anel',
        ),
      );
      expect(d.dispatch, StaleReplaceDispatch.suppress);
      expect(
        d.classification,
        StaleReplaceIntentClass.alreadyReflectedRemote,
      );
    });

    test('13. SIMPLE product valid replace preserved', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 2,
          variacoes: null,
          quantidade: 8,
        ),
        remoteData: _remote(rev: 2, variacoes: null, quantidade: 3),
      );
      expect(d.dispatch, StaleReplaceDispatch.sendReplaceOnce);
    });

    test('14. variation valid replace preserved', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 3,
          variacoes: {
            'P': {'sem-cor': 1},
            'M': {'sem-cor': 2},
          },
          quantidade: 3,
        ),
        remoteData: _remote(
          rev: 3,
          variacoes: {
            'P': {'sem-cor': 1},
            'M': {'sem-cor': 1},
          },
          quantidade: 2,
        ),
      );
      expect(d.dispatch, StaleReplaceDispatch.sendReplaceOnce);
    });

    test('15. create preserved (not-replace passthrough)', () {
      final intent = ProdutoStockCatalogCadastroIntent(
        operationId: 'op-c',
        kind: 'create',
        items: [
          {'productId': 'p1'},
        ],
        editorial: {'nome': 'Novo'},
        definition: {'quantidade': 1},
      );
      final d = ProdutoStaleReplaceIntent.classify(intent: intent);
      expect(d.classification, StaleReplaceIntentClass.notReplace);
      expect(d.dispatch, StaleReplaceDispatch.passthrough);
    });

    test('16. delete preserved (not-replace passthrough)', () {
      final intent = ProdutoStockCatalogCadastroIntent(
        operationId: 'op-d',
        kind: 'delete',
        items: [
          {'productId': 'p1', 'expectedRevision': 2},
        ],
        editorial: const {},
        expectedRevision: 2,
      );
      final d = ProdutoStaleReplaceIntent.classify(intent: intent);
      expect(d.dispatch, StaleReplaceDispatch.passthrough);
    });

    test('17. EPT cannot resurrect remote zero', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 0,
          variacoes: {
            '21': {'sem-cor': 0},
          },
          quantidade: 0,
        ),
        remoteData: _remote(
          rev: 4,
          variacoes: {
            '21': {'sem-cor': 0},
          },
          quantidade: 0,
          ept: const {'21': 7},
        ),
        frozenQueueIntent: true,
      );
      // Canonical zeros match; EPT projection ignored → suppress, no resurrect.
      expect(d.sendsReplace, isFalse);
      expect(d.dispatch, StaleReplaceDispatch.suppress);
    });

    test('18. remote canonical positive variation preserved', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 1,
          variacoes: {
            '15': {'sem-cor': 0},
          },
          quantidade: 0,
        ),
        remoteData: _remote(
          rev: 8,
          variacoes: {
            '15': {'sem-cor': 4},
          },
          quantidade: 4,
        ),
        frozenQueueIntent: true,
      );
      expect(d.sendsReplace, isFalse);
      expect(d.dispatch, StaleReplaceDispatch.blockConflict);
    });

    test('19. older queued intent cannot overtake newer', () {
      expect(
        ProdutoStaleReplaceIntent.olderIntentMustYield(
          thisCreatedAt: 100,
          thisExpectedRevision: 3,
          peers: const [
            StaleReplacePeer(createdAt: 200, expectedRevision: 5),
          ],
        ),
        isTrue,
      );
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(expectedRevision: 3),
        remoteData: _remote(rev: 3),
        intentCreatedAt: 100,
        newerPeers: const [
          StaleReplacePeer(createdAt: 200, expectedRevision: 5),
        ],
      );
      expect(d.dispatch, StaleReplaceDispatch.suppress);
      expect(d.reason, 'older-intent-overtaken');
    });

    test('20. queue order remains deterministic (createdAt peer)', () {
      expect(
        ProdutoStaleReplaceIntent.olderIntentMustYield(
          thisCreatedAt: 10,
          thisExpectedRevision: 4,
          peers: const [
            StaleReplacePeer(createdAt: 11, expectedRevision: 4),
          ],
        ),
        isTrue,
      );
      expect(
        ProdutoStaleReplaceIntent.olderIntentMustYield(
          thisCreatedAt: 20,
          thisExpectedRevision: 4,
          peers: const [
            StaleReplacePeer(createdAt: 11, expectedRevision: 4),
          ],
        ),
        isFalse,
      );
    });

    test('empty-structure stale payload cannot wipe remote grade', () {
      final d = ProdutoStaleReplaceIntent.classify(
        intent: _replace(
          expectedRevision: 1,
          variacoes: const {},
          quantidade: 1,
        ),
        remoteData: _remote(
          rev: 4,
          variacoes: {
            '21': {'sem-cor': 1},
          },
          quantidade: 1,
        ),
        frozenQueueIntent: true,
      );
      expect(d.sendsReplace, isFalse);
      expect(d.dispatch, StaleReplaceDispatch.blockConflict);
    });

    test('saved-sale limit smoke still 25', () {
      expect(StockCatalogAffectedProducts.maxAffectedProducts, 25);
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 25,
          restockCount: 0,
        ),
        returnsNormally,
      );
      expect(
        () => StockCatalogAffectedProducts.assertCommandsWithinLimit(
          saleCount: 26,
          restockCount: 0,
        ),
        throwsA(isA<SavedSaleStockSizeLimitException>()),
      );
    });

    test('unavailable remains retryable transport', () {
      final err = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'try again',
      );
      expect(
        ProdutoStockCatalogCadastroSync.isRetryableTransportError(err),
        isTrue,
      );
    });
  });
}
