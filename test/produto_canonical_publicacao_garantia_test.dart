// Auditoria: garantia de publicação canônica após offline, fila e retry.
// Somente testes — comprova comportamento atual do código de produção.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/catalogo_live_inline_policy.dart';
import 'package:master_palm/services/catalogo_queue_publish_plan.dart';
import 'package:master_palm/services/catalogo_sync_attempt_context.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/produto_cadastro_pos_save_service.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/produto_sync_fila_retry_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _lojaId = 'loja-garantia-canonical';
const _docId = 'prod-garantia-canonical';

Produto _produtoPublicado() {
  return Produto(
    nome: 'Produto Garantia',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: 3,
    precoUnitario: 50,
    categoria: 'Anel',
    dataEntrada: DateTime(2026, 6, 8),
    descricao: 'Teste garantia',
    lojaId: _lojaId,
    idFirebase: _docId,
    slug: _docId,
    publicadoNoCatalogo: true,
    updatedAt: DateTime(2026, 6, 8, 12),
    custoEditadoNoCadastro: true,
  );
}

Future<Map<String, dynamic>> _remoteCounts(
  FakeFirebaseFirestore fake,
) async {
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

/// Orquestração idêntica ao formulário online (save confirmado).
Future<Map<String, dynamic>> _formSaveOnlineOrchestration(
  Produto p, {
  required FakeFirebaseFirestore fake,
}) async {
  final ctx = CatalogoSyncAttemptContext.synthetic(
    attemptId: const Uuid().v4(),
    startedAtUtc: DateTime.now().toUtc(),
  );
  final status = await ProdutosFirestoreService.syncProdutoComStatus(
    p,
    lojaId: _lojaId,
    forcePushFromCadastro: true,
    writeOrigin: 'test.form.online',
    enqueueOnFailure: false,
    catalogoDiagContext: ctx,
    catalogoLiveInlinePolicy:
        CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
  );
  await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
    produto: p,
    lojaId: _lojaId,
    remoteStatus: status,
    catalogoDiagContext: ctx,
  );
  return _remoteCounts(fake);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveRoot;
  late String produtosBoxName;
  late Box<Produto> produtosBox;
  late FakeFirebaseFirestore fake;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    hiveRoot = Directory.systemTemp.createTempSync('garantia_canonical_');
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
    ProdutosFirestoreService.limparFalhasUpsertCatalogo();

    produtosBoxName =
        '${HiveBoxNames.produtos(_lojaId)}_${DateTime.now().microsecondsSinceEpoch}';
    produtosBox = await Hive.openBox<Produto>(produtosBoxName);
    await SyncQueueService.init();
    SyncQueueService.resetCanonicalPhaseCountersForTests();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugInlineUpsertCallCount = 0;
    CatalogoSyncService.debugFirestoreOverride = null;
    CatalogoSyncService.debugForceUpsertFailureTarget = null;
    ProdutosFirestoreService.limparFalhasUpsertCatalogo();
    await SyncQueueService.clearQueue();
    if (produtosBox.isOpen) {
      await produtosBox.close();
    }
  });

  tearDownAll(() {
    try {
      hiveRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Produto> addProduto() async {
    final p = _produtoPublicado();
    await produtosBox.add(p);
    return produtosBox.getAt(0)!;
  }

  group('save online — orquestração do formulário', () {
    test('ignora inline, publica draft+live, sem aviso amarelo', () async {
      final p = await addProduto();
      final ctx = CatalogoSyncAttemptContext.synthetic(
        attemptId: const Uuid().v4(),
        startedAtUtc: DateTime.now().toUtc(),
      );

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
        enqueueOnFailure: false,
        catalogoDiagContext: ctx,
        catalogoLiveInlinePolicy:
            CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);
      expect(ProdutosFirestoreService.debugInlineUpsertCallCount, 0);

      await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
        produto: p,
        lojaId: _lojaId,
        remoteStatus: status,
        catalogoDiagContext: ctx,
      );

      final counts = await _remoteCounts(fake);
      expect(counts['estoque'], isTrue);
      expect(counts['draft'], isTrue);
      expect(counts['live'], isTrue);
      expect(
        ProdutosFirestoreService.falhasCanonicalDoAttempt(ctx.attemptId),
        isEmpty,
      );
    });
  });

  group('save offline / fila — publicação canônica na fila', () {
    test('falha remota enfileira com plan canonico e pós-save não roda no save',
        () async {
      final p = await addProduto();
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 999;

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
        writeOrigin: CatalogoQueueSourceOrigins.produtoFormSave,
        enqueueOnFailure: true,
        catalogoLiveInlinePolicy:
            CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
      );

      expect(status, ProdutoSyncRemotoStatus.pendenteFila);
      expect(await SyncQueueService.activePendingCount(), 1);

      final item = await SyncQueueService.findProdutoQueueItem(
        lojaId: _lojaId,
        entityKey: p.key as int,
      );
      expect(item!.catalogoPublishPlan,
          CatalogoQueuePublishPlan.canonicoAposEstoque);

      final posSave = await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
        produto: p,
        lojaId: _lojaId,
        remoteStatus: status,
      );
      expect(posSave, isNull);

      final counts = await _remoteCounts(fake);
      expect(counts['estoque'], isFalse);
      expect(counts['draft'], isFalse);
      expect(counts['live'], isFalse);
    });

    test('processPending canônico publica estoque+draft+live', () async {
      final p = await addProduto();
      final key = p.key as int;

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

      ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
      final r = await SyncQueueService.processPending();
      expect(r.processed, 1);

      final counts = await _remoteCounts(fake);
      expect(counts['estoque'], isTrue);
      expect(counts['draft'], isTrue);
      expect(counts['live'], isTrue);
      expect(ProdutosFirestoreService.debugInlineUpsertCallCount, 0);
    });

    test('reinício simulado: processPending canônico completa draft+live',
        () async {
      final p = await addProduto();
      final key = p.key as int;

      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: _lojaId,
        boxName: produtosBoxName,
        entityKey: key,
        catalogoPublishPlan: CatalogoQueuePublishPlan.canonicoAposEstoque,
        catalogoPublishPhase: CatalogoQueuePublishPhase.aguardandoEstoque,
        scheduleProcess: false,
      );

      await produtosBox.close();
      produtosBox = await Hive.openBox<Produto>(produtosBoxName);

      await SyncQueueService.processPending();

      final counts = await _remoteCounts(fake);
      expect(counts['estoque'], isTrue);
      expect(counts['draft'], isTrue);
      expect(counts['live'], isTrue);
    });
  });

  group('retry — formulário vs fila isolada', () {
    test('retry do formulário com pós-save publica draft+live', () async {
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 1;
      final p = await addProduto();
      final ctx = CatalogoSyncAttemptContext.synthetic(
        attemptId: const Uuid().v4(),
        startedAtUtc: DateTime.now().toUtc(),
      );

      final status = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
        p,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
        catalogoDiagContext: ctx,
        catalogoLiveInlinePolicy:
            CatalogoLiveInlinePolicy.ignorarPorquePosSaveCanonico,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
        produto: p,
        lojaId: _lojaId,
        remoteStatus: status,
        catalogoDiagContext: ctx,
      );

      final counts = await _remoteCounts(fake);
      expect(counts['draft'], isTrue);
      expect(counts['live'], isTrue);
    });

    test('retry da fila legada sem metadado não publica draft', () async {
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 1;
      final p = await addProduto();

      final status = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
        p,
        lojaId: _lojaId,
        forcePushFromCadastro: true,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final counts = await _remoteCounts(fake);
      expect(counts['estoque'], isTrue);
      expect(counts['live'], isTrue);
      expect(counts['draft'], isFalse);
    });
  });

  group('persistir produto atual — mesma orquestração', () {
    test('_persistirProdutoAtual equivalente publica draft+live', () async {
      final p = await addProduto();
      final counts = await _formSaveOnlineOrchestration(p, fake: fake);
      expect(counts['draft'], isTrue);
      expect(counts['live'], isTrue);
    });
  });

  group('dead-letter', () {
    test('não publica catálogo e marca deadLetter após esgotar tentativas',
        () async {
      final p = await addProduto();
      final key = p.key as int;

      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: _lojaId,
        boxName: produtosBoxName,
        entityKey: key,
      );

      ProdutosFirestoreService.debugForceSyncFailureRemaining = 999;
      for (var i = 0; i < 5; i++) {
        await SyncQueueService.processPending();
      }

      final entries = await SyncQueueService.listDiagnosticEntries();
      expect(entries.length, 1);
      expect(entries.first.deadLetter, isTrue);

      final counts = await _remoteCounts(fake);
      expect(counts['estoque'], isFalse);
      expect(counts['draft'], isFalse);
      expect(counts['live'], isFalse);
    });
  });

  group('isolamento attemptId', () {
    test('falha inline legado não contamina attemptId do formulário', () async {
      final formAttempt = const Uuid().v4();
      ProdutosFirestoreService.registrarFalhaUpsertCatalogo(
        lojaId: _lojaId,
        produtoId: _docId,
        path: 'lojas/$_lojaId/produtos/$_docId',
        operacao: 'upsert_produtos_live_inline',
        error: Exception('permission-denied'),
        attemptId: 'legacy-attempt',
        origin: 'sync_queue.upsert_produto',
      );

      expect(
        ProdutosFirestoreService.falhasCanonicalDoAttempt(formAttempt),
        isEmpty,
      );
    });
  });

  group('falha real canônica', () {
    test('draft/live failure gera aviso amarelo filtrado por attemptId', () async {
      final p = await addProduto();
      final attemptId = const Uuid().v4();
      final ctx = CatalogoSyncAttemptContext.synthetic(
        attemptId: attemptId,
        startedAtUtc: DateTime.now().toUtc(),
      );

      CatalogoSyncService.debugForceUpsertFailureTarget = SyncTarget.live;
      await ProdutoCadastroPosSaveService.executarAposEstoqueRemotoOk(
        produto: p,
        lojaId: _lojaId,
        remoteStatus: ProdutoSyncRemotoStatus.confirmado,
        catalogoDiagContext: ctx,
      );

      final falhas =
          ProdutosFirestoreService.falhasCanonicalDoAttempt(attemptId);
      expect(falhas.length, 1);
      expect(falhas.first.operacao, 'upsert_produtos_live');
      final msg = ProdutoSyncErroUtil.mensagemCadastroFalhaParcialCatalogo(
        falhas: falhas,
      );
      expect(msg, contains('catálogo/draft'));
    });
  });
}
