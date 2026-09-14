import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    StockCatalogBackendService.debugTransport = null;
  });

  test('create uses backend protocol with private cost in definition only',
      () async {
    final produto = Produto.vazio()
      ..nome = 'Camisa'
      ..slug = 'camisa'
      ..idFirebase = 'prod-1'
      ..quantidade = 3
      ..custoReal = 12.5
      ..publicadoNoCatalogo = true
      ..stockRevision = 0;

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: 'prod-1',
      documentExists: false,
      forcePushFromCadastro: true,
      gradeBaseline: ProdutoFormGradeBaseline.capture(produto),
    );

    expect(intent.kind, 'create');
    expect(intent.definition?['quantidade'], 3);
    expect(intent.definition?['custoReal'], 12.5);
    expect(intent.editorial.containsKey('custoReal'), isFalse);
    expect(intent.editorial.containsKey('quantidade'), isFalse);
    expect(hasPendingStockMutation(produto), isTrue);
    expect(produto.pendingStockOperationId, intent.operationId);
  });

  test('OBSERVED_REVISION_SOURCE is form baseline, not remote save refresh',
      () async {
    final produto = Produto.vazio()
      ..idFirebase = 'prod-2'
      ..quantidade = 5
      ..stockRevision = 4;
    final baseline = ProdutoFormGradeBaseline(
      stockRevision: 4,
      quantidade: 5,
    );
    // Simula mutação local na sessão após abertura.
    produto.quantidade = 9;
    produto.stockRevision = 99; // NÃO deve abençoar CAS.

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: 'prod-2',
      documentExists: true,
      forcePushFromCadastro: true,
      gradeBaseline: baseline,
    );

    expect(intent.kind, 'replace');
    expect(intent.expectedRevision, 4);
    expect(
      ProdutoStockCatalogCadastroSync.observedRevisionForSave(
        produto: produto,
        gradeBaseline: baseline,
      ),
      4,
    );
    expect(
      ProdutoStockCatalogCadastroSync
          .saveDoesNotRefreshRevisionToValidateOldSnapshot(
        observedRevision: 4,
        remoteRevisionAtSaveTime: 99,
      ),
      isTrue,
    );
  });

  test('auto sync without pending intent stays editorial (not stock restock)',
      () async {
    final produto = Produto.vazio()
      ..idFirebase = 'prod-3'
      ..nome = 'Nome novo'
      ..quantidade = 1
      ..stockRevision = 2;

    final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
      produto: produto,
      produtoId: 'prod-3',
      documentExists: true,
      forcePushFromCadastro: false,
    );

    expect(intent.kind, 'editorial');
    expect(intent.definition, isNull);
    expect(intent.editorial['nome'], 'Nome novo');
  });

  test('OFFLINE_INTENT survives encode/decode with same operationId', () {
    final intent = ProdutoStockCatalogCadastroIntent(
      operationId: 'op-stable-1',
      kind: 'replace',
      items: [
        {'productId': 'p', 'expectedRevision': 3},
      ],
      editorial: {'nome': 'A'},
      definition: {'quantidade': 2, 'custoReal': 1.0},
      expectedRevision: 3,
    );
    final restored =
        ProdutoStockCatalogCadastroIntent.tryDecode(intent.encode());
    expect(restored, isNotNull);
    expect(restored!.operationId, 'op-stable-1');
    expect(restored.kind, 'replace');
    expect(restored.expectedRevision, 3);
    expect(restored.definition?['quantidade'], 2);
  });

  test('queue item persists stockIntentJson across restart map roundtrip', () {
    final item = SyncQueueItem(
      id: 'q1',
      type: SyncOperationType.upsertProduto,
      lojaId: 'loja',
      boxName: 'produtos_loja',
      entityKey: 7,
      createdAt: 1,
      stockIntentJson: ProdutoStockCatalogCadastroIntent(
        operationId: 'op-restart',
        kind: 'create',
        items: [
          {'productId': 'p'}
        ],
        editorial: {'nome': 'X'},
        definition: {'quantidade': 1},
      ).encode(),
    );
    final restored = SyncQueueItem.fromMap(item.toMap());
    expect(restored.stockIntentJson, isNotNull);
    final intent =
        ProdutoStockCatalogCadastroIntent.tryDecode(restored.stockIntentJson);
    expect(intent?.operationId, 'op-restart');
    expect(intent?.kind, 'create');
  });

  test('retry reuses frozen intent identity via transport', () async {
    final calls = <Map<String, dynamic>>[];
    StockCatalogBackendService.debugTransport = (name, data) async {
      calls.add(Map<String, dynamic>.from(data));
      return {
        'operationId': data['operationId'],
        'alreadyApplied': calls.length > 1,
        'products': [
          {
            'productId': 'p',
            'quantidade': 1,
            'stockRevision': 1,
            'variacoes': <String, dynamic>{},
            'estoquePorTamanho': <String, dynamic>{},
          }
        ],
      };
    };

    final frozen = ProdutoStockCatalogCadastroIntent(
      operationId: 'op-retry',
      kind: 'create',
      items: [
        {'productId': 'p'}
      ],
      editorial: {'nome': 'Y', 'publicadoNoCatalogo': true},
      definition: {'quantidade': 1, 'custoReal': 2.0},
    );

    await ProdutoStockCatalogCadastroSync.sendIntent(
      lojaId: 'loja',
      intent: frozen,
    );
    await ProdutoStockCatalogCadastroSync.sendIntent(
      lojaId: 'loja',
      intent: frozen,
    );

    expect(calls.length, 2);
    expect(calls[0]['operationId'], 'op-retry');
    expect(calls[1]['operationId'], 'op-retry');
    expect(calls[0], calls[1]);
  });
}
