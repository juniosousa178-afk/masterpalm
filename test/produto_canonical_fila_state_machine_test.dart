// Máquina de estados canônica na fila offline: plan, phase, retry idempotente.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_live_inline_policy.dart';
import 'package:master_palm/services/catalogo_queue_publish_plan.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-fila-canonical';
const _docId = 'prod-fila-canonical';

Produto _produto() {
  return Produto(
    nome: 'Produto Fila',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 40,
    quantidade: 2,
    precoUnitario: 40,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 6, 8),
    descricao: 'Teste fila',
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    publicadoNoCatalogo: true,
    updatedAt: DateTime(2026, 6, 8, 12),
    custoEditadoNoCadastro: true,
  );
}

Future<Map<String, bool>> _remoteCounts(FakeFirebaseFirestore fake) async {
  final estoque = await fake
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_produtos')
      .doc(_docId)
      .get();
  final draft = await fake
      .collection('lojas')
      .doc(_lojaId)
      .collection('draft_produtos')
      .doc(_docId)
      .get();
  final live = await fake
      .collection('lojas')
      .doc(_lojaId)
      .collection('produtos')
      .doc(_docId)
      .get();
  return {
    'estoque': estoque.exists,
    'draft': draft.exists,
    'live': live.exists,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveRoot;
  late String produtosBoxName;
  late Box<Produto> produtosBox;
  late FakeFirebaseFirestore fake;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hiveRoot = Directory.systemTemp.createTempSync('fila_canonical_sm_');
    Hive.init(hiveRoot.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  setUp(() async {
    fake = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    CatalogoSyncService.debugFirestoreOverride = fake;
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.debugInlineUpsertCallCount = 0;
    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    SyncQueueService.resetCanonicalPhaseCountersForTests();

    produtosBoxName =
        '${HiveBoxNames.produtos(_lojaId)}_${DateTime.now().microsecondsSinceEpoch}';
    produtosBox = await Hive.openBox<Produto>(produtosBoxName);
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugInlineUpsertCallCount = 0;
    CatalogoSyncService.debugFirestoreOverride = null;
    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    await SyncQueueService.clearQueue();
    if (produtosBox.isOpen) await produtosBox.close();
  });

  tearDownAll(() {
    try {
      hiveRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(Produto, int)> addProduto() async {
    await produtosBox.add(_produto());
    final p = produtosBox.getAt(0)!;
    return (p, p.key as int);
  }

  Future<void> enqueueCanonicoForm(int key) async {
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: _lojaId,
      boxName: produtosBoxName,
      entityKey: key,
      catalogoPublishPlan: CatalogoQueuePublishPlan.canonicoAposEstoque,
      catalogoPublishPhase: CatalogoQueuePublishPhase.aguardandoEstoque,
      catalogoQueueSourceOrigin: CatalogoQueueSourceOrigins.produtoFormSave,
      scheduleProcess: false,
    );
  }

  test('save offline formulário enfileira plan canonico e phase aguardandoEstoque',
      () async {
    final (_, key) = await addProduto();
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 999;

    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      produtosBox.get(key)!,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      writeOrigin: CatalogoQueueSourceOrigins.produtoFormSave,
      enqueueOnFailure: true,
      catalogoLiveInlinePolicy:
          CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
    );

    expect(status, ProdutoSyncRemotoStatus.pendenteFila);
    final item = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key,
    );
    expect(item, isNotNull);
    expect(item!.catalogoPublishPlan,
        CatalogoQueuePublishPlan.canonicoAposEstoque);
    expect(item.catalogoPublishPhase,
        CatalogoQueuePublishPhase.aguardandoEstoque);
    expect(item.catalogoQueueSourceOrigin,
        CatalogoQueueSourceOrigins.produtoFormSave);
  });

  test('item legado sem metadados mantém plan legadoInline', () async {
    final (_, key) = await addProduto();
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: _lojaId,
      boxName: produtosBoxName,
      entityKey: key,
      scheduleProcess: false,
    );
    final item = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key,
    );
    expect(item!.catalogoPublishPlan, CatalogoQueuePublishPlan.legadoInline);
    expect(item.catalogoPublishPhase,
        CatalogoQueuePublishPhase.aguardandoEstoque);
  });

  test('reconexão canônica: estoque → draft → live → item removido', () async {
    final (_, key) = await addProduto();
    await enqueueCanonicoForm(key);

    final r = await SyncQueueService.processPending();
    expect(r.processed, 1);
    expect(await SyncQueueService.activePendingCount(), 0);

    expect(SyncQueueService.debugCanonicalPhaseEstoqueRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseLiveRuns, 1);
    expect(ProdutosFirestoreService.debugInlineUpsertCallCount, 0);

    final counts = await _remoteCounts(fake);
    expect(counts['estoque'], isTrue);
    expect(counts['draft'], isTrue);
    expect(counts['live'], isTrue);
  });

  test('falha em draft mantém aguardandoDraft e retry não repete estoque', () async {
    final (_, key) = await addProduto();
    await enqueueCanonicoForm(key);

    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.draft;
    await SyncQueueService.processPending();

    expect(SyncQueueService.debugCanonicalPhaseEstoqueRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseLiveRuns, 0);

    final counts = await _remoteCounts(fake);
    expect(counts['estoque'], isTrue);
    expect(counts['draft'], isFalse);

    final item = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key,
    );
    expect(item!.catalogoPublishPhase,
        CatalogoQueuePublishPhase.aguardandoDraft);

    SyncQueueService.resetCanonicalPhaseCountersForTests();
    CatalogoSyncService.debugForceUpsertFailureTarget = null;

    await SyncQueueService.processPending();
    expect(SyncQueueService.debugCanonicalPhaseEstoqueRuns, 0);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseLiveRuns, 1);

    final counts2 = await _remoteCounts(fake);
    expect(counts2['draft'], isTrue);
    expect(counts2['live'], isTrue);
  });

  test('falha em live mantém aguardandoLive e retry não repete estoque/draft',
      () async {
    final (_, key) = await addProduto();
    await enqueueCanonicoForm(key);

    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.live;
    await SyncQueueService.processPending();

    expect(SyncQueueService.debugCanonicalPhaseEstoqueRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseLiveRuns, 1);

    final counts = await _remoteCounts(fake);
    expect(counts['estoque'], isTrue);
    expect(counts['draft'], isTrue);
    expect(counts['live'], isFalse);

    final item = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key,
    );
    expect(item!.catalogoPublishPhase, CatalogoQueuePublishPhase.aguardandoLive);

    SyncQueueService.resetCanonicalPhaseCountersForTests();
    CatalogoSyncService.debugForceUpsertFailureTarget = null;

    await SyncQueueService.processPending();
    expect(SyncQueueService.debugCanonicalPhaseEstoqueRuns, 0);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 0);
    expect(SyncQueueService.debugCanonicalPhaseLiveRuns, 1);

    expect((await _remoteCounts(fake))['live'], isTrue);
  });

  test('reinício simulado em aguardandoDraft completa live automaticamente',
      () async {
    final (_, key) = await addProduto();
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: _lojaId,
      boxName: produtosBoxName,
      entityKey: key,
      catalogoPublishPlan: CatalogoQueuePublishPlan.canonicoAposEstoque,
      catalogoPublishPhase: CatalogoQueuePublishPhase.aguardandoDraft,
      catalogoQueueSourceOrigin: CatalogoQueueSourceOrigins.produtoFormSave,
      scheduleProcess: false,
    );
    // Simula estoque já confirmado antes do reinício
    await ProdutosFirestoreService.syncProdutoComStatus(
      produtosBox.get(key)!,
      lojaId: _lojaId,
      forcePushFromCadastro: true,
      enqueueOnFailure: false,
      catalogoLiveInlinePolicy:
          CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
    );

    await produtosBox.close();
    produtosBox = await Hive.openBox<Produto>(produtosBoxName);

    await SyncQueueService.processPending();

    expect(SyncQueueService.debugCanonicalPhaseEstoqueRuns, 0);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 1);
    expect(SyncQueueService.debugCanonicalPhaseLiveRuns, 1);
    expect(await SyncQueueService.activePendingCount(), 0);
  });

  test('dead-letter em draft preserva phase e não publica live', () async {
    final (_, key) = await addProduto();
    await enqueueCanonicoForm(key);
    CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.draft;

    for (var i = 0; i < 5; i++) {
      await SyncQueueService.processPending();
    }

    final item = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key,
    );
    expect(item!.deadLetter, isTrue);
    expect(item.catalogoPublishPhase,
        CatalogoQueuePublishPhase.aguardandoDraft);

    final counts = await _remoteCounts(fake);
    expect(counts['estoque'], isTrue);
    expect(counts['draft'], isFalse);
    expect(counts['live'], isFalse);
  });

  test('item legado usa inline e não publica draft automaticamente', () async {
    final (_, key) = await addProduto();
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: _lojaId,
      boxName: produtosBoxName,
      entityKey: key,
      scheduleProcess: false,
    );

    await SyncQueueService.processPending();

    final counts = await _remoteCounts(fake);
    expect(counts['estoque'], isTrue);
    expect(counts['live'], isTrue);
    expect(counts['draft'], isFalse);
    expect(SyncQueueService.debugCanonicalPhaseDraftRuns, 0);
  });

  test('dois produtos canônicos não misturam fase na fila', () async {
    final (_, key1) = await addProduto();
    final p2 = _produto()
      ..idFirebase = 'prod-fila-2'
      ..slug = 'prod-fila-2'
      ..nome = 'Produto 2';
    await produtosBox.add(p2);
    final key2 = produtosBox.getAt(1)!.key as int;

    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: _lojaId,
      boxName: produtosBoxName,
      entityKey: key1,
      catalogoPublishPlan: CatalogoQueuePublishPlan.canonicoAposEstoque,
      catalogoPublishPhase: CatalogoQueuePublishPhase.aguardandoLive,
      catalogoQueueSourceOrigin: CatalogoQueueSourceOrigins.produtoFormSave,
      scheduleProcess: false,
    );
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: _lojaId,
      boxName: produtosBoxName,
      entityKey: key2,
      catalogoPublishPlan: CatalogoQueuePublishPlan.canonicoAposEstoque,
      catalogoPublishPhase: CatalogoQueuePublishPhase.aguardandoEstoque,
      catalogoQueueSourceOrigin: CatalogoQueueSourceOrigins.produtoFormPersistirAtual,
      scheduleProcess: false,
    );

    // Pré-popula estoque/draft do produto 1 (fase aguardandoLive)
    await ProdutosFirestoreService.syncProdutoComStatus(
      produtosBox.get(key1)!,
      lojaId: _lojaId,
      enqueueOnFailure: false,
      catalogoLiveInlinePolicy:
          CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
    );
    await CatalogoSyncService.upsertFromProduto(
      produtosBox.get(key1)!,
      target: SyncTarget.draft,
      lojaIdOverride: _lojaId,
    );

    await SyncQueueService.processPending();

    final i1 = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key1,
    );
    final i2 = await SyncQueueService.findProdutoQueueItem(
      lojaId: _lojaId,
      entityKey: key2,
    );
    expect(i1, isNull, reason: 'produto1 live OK → removido');
    expect(i2, isNull, reason: 'produto2 fluxo completo → removido');
  });
}
