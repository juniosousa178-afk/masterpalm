// Fila de sync de produto novo: processamento e retentativa após falha transitória.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/dart_error_unwrap.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_estoque_doc_id_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produto_sync_fila_retry_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:master_palm/services/venda_estoque_remoto_prep_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'nathy-pratas-e-folheados';
  const slugTeste = 'nathy-pratas-e-folheados-teste';
  const slugTesteSeguro = 'nathy-pratas-e-folheados-teste-2';
  const slugTeste11 = 'nathy-pratas-e-folheados-teste-11';

  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late String produtosBoxName;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_fila_sync_');
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
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;
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

  Future<void> tombstoneProduto(String docId) async {
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.exclusaoProdutoCol)
        .doc(docId)
        .set({'p': true});
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
  }

  Produto novoProduto({
    required String nome,
    required String docId,
  }) {
    return Produto.vazio()
      ..nome = nome
      ..slug = docId
      ..idFirebase = docId
      ..lojaId = lojaId
      ..quantidade = 1
      ..precoFinal = 10
      ..precoUnitario = 10
      ..updatedAt = DateTime.now();
  }

  group('SyncQueueService — processamento da fila', () {
    test('enqueue upsertProduto + processPending cria estoque_produtos', () async {
      final p = novoProduto(nome: 'Teste 11', docId: slugTeste11);
      await produtosBox.add(p);
      final key = p.key as int;

      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: lojaId,
        boxName: produtosBoxName,
        entityKey: key,
      );

      expect(await SyncQueueService.activePendingCount(), 1);

      final r = await SyncQueueService.processPending();
      expect(r.processed, 1);
      expect(await SyncQueueService.activePendingCount(), 0);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(slugTeste11)
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()?['nome'], 'Teste 11');
    });
  });

  group('ProdutoSyncFilaRetryService', () {
    test('falha transitória enfileira e retentativa confirma remoto', () async {
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 1;

      final p = novoProduto(nome: 'Teste 11', docId: slugTeste11);
      await produtosBox.add(p);

      final status = await ProdutoSyncFilaRetryService.syncComRetentativaFila(
        p,
        lojaId: lojaId,
      );

      expect(status, ProdutoSyncRemotoStatus.confirmado);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(slugTeste11)
          .get();
      expect(snap.exists, isTrue);

      await SyncQueueService.processPending();
      expect(await SyncQueueService.activePendingCount(), 0);
    });

    test('id seguro com tombstone no base: sincroniza com sufixo -2', () async {
      await tombstoneProduto(slugTeste);

      final docId =
          await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
        lojaId: lojaId,
        nome: 'Teste',
      );
      expect(docId, slugTesteSeguro);

      final p = novoProduto(nome: 'Teste', docId: docId);
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
                .doc(slugTesteSeguro)
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
  });

  group('VendaEstoqueRemotoPrepService — após fila', () {
    test('após fila processada, prep permite baixa', () async {
      final p = novoProduto(nome: 'Teste 11', docId: slugTeste11);
      await produtosBox.add(p);
      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: lojaId,
        boxName: produtosBoxName,
        entityKey: p.key as int,
      );
      await SyncQueueService.processPending();

      await VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
        lojaId: lojaId,
        produtos: [p],
      );

      expect(
        await VendaEstoqueRemotoPrepService.estoqueDocExisteRemoto(
          lojaId: lojaId,
          produto: p,
        ),
        isTrue,
      );
    });

    test('só Hive sem doc remoto: bloqueia com mensagem de sincronizando', () async {
      ProdutosFirestoreService.debugForceSyncFailureRemaining = 99;

      final p = novoProduto(nome: 'Teste 11', docId: slugTeste11);
      await produtosBox.add(p);

      await expectLater(
        VendaEstoqueRemotoPrepService.garantirProdutosProntosParaBaixa(
          lojaId: lojaId,
          produtos: [p],
        ),
        throwsA(
          predicate(
            (Object e) => formatDartErrorForUser(e).contains('sincronizando'),
          ),
        ),
      );
    });
  });

  group('Hive — cadastro local', () {
    test('produto novo com id seguro persiste slug e idFirebase', () async {
      await tombstoneProduto(slugTeste);
      final docId =
          await ProdutoEstoqueDocIdService.resolverDocIdSeguroNovoProduto(
        lojaId: lojaId,
        nome: 'Teste 11',
      );

      final p = novoProduto(nome: 'Teste 11', docId: docId);
      await produtosBox.add(p);

      expect(p.slug, docId);
      expect(p.idFirebase, docId);
      expect(
        await produtosBox.get(p.key as int),
        isNotNull,
      );
    });
  });
}
