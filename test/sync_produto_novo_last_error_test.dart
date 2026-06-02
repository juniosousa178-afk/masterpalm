// lastError da fila de sync de produto novo + mensagens sanitizadas.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_estoque_doc_id_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/produto_sync_fila_retry_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'nathy-pratas-e-folheados';
  const slugTeste = 'nathy-pratas-e-folheados-teste';
  const slugSeguro = 'nathy-pratas-e-folheados-teste-2';

  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late String produtosBoxName;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_sync_last_err_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoSyncFilaRetryService.debugProcessPendingChamadas = 0;
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.ultimoErroSyncSanitizado = null;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBoxName = '${HiveBoxNames.produtos(lojaId)}_$s';
    produtosBox = await Hive.openBox<Produto>(produtosBoxName);
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
    await SyncQueueService.clearQueue();
    await produtosBox.close();
  });

  group('ProdutoSyncErroUtil', () {
    test('permission-denied vira mensagem curta', () {
      final msg = ProdutoSyncErroUtil.sanitizar(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );
      expect(msg, contains('permission-denied'));
    });

    test('lojaId ausente via status', () {
      expect(
        ProdutoSyncErroUtil.sanitizar(
          null,
          status: ProdutoSyncRemotoStatus.lojaInvalida,
        ),
        'lojaId ausente',
      );
    });
  });

  group('SyncQueueService — lastError', () {
    test('enqueue grava lastError na entrada inicial', () async {
      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: lojaId,
        boxName: produtosBoxName,
        entityKey: 7,
        lastError: 'permission-denied (sem permissão na loja)',
      );

      expect(
        await SyncQueueService.lastProdutoSyncErrorForEntity(
          lojaId: lojaId,
          entityKey: 7,
        ),
        contains('permission-denied'),
      );
    });

    test('sync imediato falho enfileira com erro sanitizado', () async {
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 1;

      final p = Produto.vazio()
        ..nome = 'Teste 11'
        ..slug = 'nathy-pratas-e-folheados-teste-11'
        ..idFirebase = 'nathy-pratas-e-folheados-teste-11'
        ..lojaId = lojaId
        ..quantidade = 1
        ..precoFinal = 10
        ..updatedAt = DateTime.now();
      await produtosBox.add(p);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: lojaId,
      );
      expect(status, ProdutoSyncRemotoStatus.pendenteFila);

      final err = await SyncQueueService.lastProdutoSyncErrorForEntity(
        lojaId: lojaId,
        entityKey: p.key as int,
      );
      expect(err, isNotNull);
      expect(err!, contains('debug'));
    });

    test('processPending com Firestore OK cria estoque_produtos e remove fila', () async {
      final p = Produto.vazio()
        ..nome = 'Teste 11'
        ..slug = 'nathy-pratas-e-folheados-teste-11'
        ..idFirebase = 'nathy-pratas-e-folheados-teste-11'
        ..lojaId = lojaId
        ..quantidade = 1
        ..precoFinal = 10
        ..updatedAt = DateTime.now();
      await produtosBox.add(p);

      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: lojaId,
        boxName: produtosBoxName,
        entityKey: p.key as int,
        lastError: 'unavailable (serviço indisponível)',
      );

      final r = await SyncQueueService.processPending();
      expect(r.processed, 1);
      expect(await SyncQueueService.activePendingCount(), 0);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc('nathy-pratas-e-folheados-teste-11')
          .get();
      expect(snap.exists, isTrue);
    });
  });

  group('ProdutoSyncFilaRetryService', () {
    test('retentativa chama processPending após falha imediata', () async {
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 1;

      final p = Produto.vazio()
        ..nome = 'Teste'
        ..slug = slugSeguro
        ..idFirebase = slugSeguro
        ..lojaId = lojaId
        ..quantidade = 1
        ..precoFinal = 10
        ..updatedAt = DateTime.now();
      await produtosBox.add(p);

      final status = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
        p,
        lojaId: lojaId,
      );

      expect(ProdutoSyncFilaRetryService.debugProcessPendingChamadas, 1);
      expect(status, ProdutoSyncRemotoStatus.confirmado);
    });

    test('id seguro: fila escreve no doc -2 e não no tombstonado', () async {
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(slugTeste)
          .set({'p': true});
      await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);

      final docId =
          await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
        lojaId: lojaId,
        nome: 'Teste',
      );
      expect(docId, slugSeguro);

      final p = Produto.vazio()
        ..nome = 'Teste'
        ..slug = docId
        ..idFirebase = docId
        ..lojaId = lojaId
        ..quantidade = 1
        ..precoFinal = 10
        ..updatedAt = DateTime.now();
      await produtosBox.add(p);

      final status = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
        p,
        lojaId: lojaId,
      );
      expect(status, ProdutoSyncRemotoStatus.confirmado);

      expect(
        (await firestore
                .collection('lojas')
                .doc(lojaId)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(slugSeguro)
                .get())
            .exists,
        isTrue,
      );
      expect(
        (await firestore
                .collection('lojas')
                .doc(lojaId)
                .collection(FSPaths.estoqueProdutosCol)
                .doc(slugTeste)
                .get())
            .exists,
        isFalse,
      );
    });

    test('lojaId vazio retorna lojaInvalida com erro sanitizado', () async {
      final p = Produto.vazio()
        ..nome = 'X'
        ..slug = 'x'
        ..lojaId = ''
        ..quantidade = 1
        ..precoFinal = 1
        ..updatedAt = DateTime.now();
      await produtosBox.add(p);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: '',
        enqueueOnFailure: true,
      );
      expect(status, ProdutoSyncRemotoStatus.lojaInvalida);
      expect(ProdutosFirestoreService.ultimoErroSyncSanitizado, 'lojaId ausente');
    });
  });
}
