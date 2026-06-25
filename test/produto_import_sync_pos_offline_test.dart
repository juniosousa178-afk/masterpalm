// Sync pós-importação offline: tombstone, colisão, fila e reidentificação.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/produto_firestore_doc_id_validator.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_estoque_doc_id_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produto_import_doc_id_helper.dart';
import 'package:master_palm/services/produto_import_service.dart';
import 'package:master_palm/services/produto_import_sync_prep_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaId = 'loja-sync-pos-import';
  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late String produtosBoxName;
  late Box<Venda> vendasBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_sync_pos_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(VendaAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(VendaItemAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugForceSyncFailureRemaining = 0;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBoxName = '${HiveBoxNames.produtos(lojaId)}_$s';
    produtosBox = await Hive.openBox<Produto>(produtosBoxName);
    vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId));
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
  });

  tearDown(() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
    await SyncQueueService.clearQueue();
    await produtosBox.close();
    await vendasBox.close();
  });

  Produto linha({required String nome, int qtd = 2}) {
    return Produto(
      nome: nome,
      custoReal: 1,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 10,
      quantidade: qtd,
      precoUnitario: 10,
      categoria: 'Cat',
      dataEntrada: DateTime.now(),
      lojaId: lojaId,
    );
  }

  Future<void> tombstone(String docId) async {
    await firestore
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.exclusaoProdutoCol)
        .doc(docId)
        .set({'p': true});
    await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);
  }

  Future<Produto> importarOffline(String nome) async {
    final r = await ProdutoImportService.processarLinha(
      linha: 1,
      produto: linha(nome: nome),
      lojaId: lojaId,
      produtosBox: produtosBox,
      vendasBox: vendasBox,
    );
    expect(r.status, ProdutoImportLinhaStatus.pendenteSincronizacao);
    expect(r.produto, isNotNull);
    expect(ProdutoImportDocIdHelper.isDocIdLocalImportacao(r.produto!.slug),
        isTrue);
    return r.produto!;
  }

  group('sync pós-importação', () {
    test('2. sync online sem colisão confirma remoto e limpa fila', () async {
      final p = await importarOffline('Sync Livre');
      final localId = p.slug;

      final r = await SyncQueueService.processPending();
      expect(r.processed, greaterThanOrEqualTo(1));

      final remotoId = p.idFirebase.isNotEmpty ? p.idFirebase : p.slug;
      expect(remotoId, isNot(localId));
      expect(ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(remotoId), isTrue);

      final snap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(remotoId)
          .get();
      expect(snap.exists, isTrue);
      expect(await SyncQueueService.activePendingCount(), 0);
    });

    test('3. tombstone no id canônico → reidentifica para sufixo e preserva tombstone',
        () async {
      final base = ProdutoEstoqueDocIdService.slugCanonicoParaLoja(
        lojaId: lojaId,
        nome: 'Coracao Tombstone',
      );
      await tombstone(base);

      final p = await importarOffline('Coracao Tombstone');
      final importLocal = p.slug;

      await SyncQueueService.processPending();

      final remotoId = p.slug;
      expect(remotoId, '$base-2');
      expect(remotoId, isNot(importLocal));

      final tombSnap = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(base)
          .get();
      expect(tombSnap.data()?['p'], isTrue);

      final docA = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(base)
          .get();
      expect(docA.exists, isFalse);

      final docB = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(remotoId)
          .get();
      expect(docB.exists, isTrue);
    });

    test('4. doc remoto existente no canônico → novo id sem sobrescrever A', () async {
      final base = ProdutoEstoqueDocIdService.slugCanonicoParaLoja(
        lojaId: lojaId,
        nome: 'Doc Existente',
      );
      await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(base)
          .set({'nome': 'Remoto Legado', 'quantidade': 99});

      final p = await importarOffline('Doc Existente');
      await SyncQueueService.processPending();

      expect(p.slug, '$base-2');
      final legado = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(base)
          .get();
      expect(legado.data()?['quantidade'], 99);
    });

    test('5. produto com venda + tombstone → recuperacaoManualNecessaria', () async {
      final base = ProdutoEstoqueDocIdService.slugCanonicoParaLoja(
        lojaId: lojaId,
        nome: 'Com Venda Tomb',
      );
      final existente = linha(nome: 'Com Venda Tomb');
      existente.slug = base;
      existente.idFirebase = base;
      await produtosBox.add(existente);
      await existente.save();
      await tombstone(base);

      await vendasBox.add(
        Venda(
          clienteNome: 'C',
          produtosDescricao: existente.nome,
          quantidade: 1,
          preco: 10,
          total: 10,
          formasPagamento: 'pix',
          data: DateTime.now(),
          vendedor: 'v',
          observacao: '',
          lojaId: lojaId,
          itens: [
            VendaItem(
              produtoNome: existente.nome,
              quantidade: 1,
              precoUnitario: 10,
              productId: base,
            ),
          ],
        ),
      );

      await SyncQueueService.enqueue(
        type: SyncOperationType.upsertProduto,
        lojaId: lojaId,
        boxName: produtosBoxName,
        entityKey: existente.key as int,
      );

      final antesSlug = existente.slug;
      await SyncQueueService.processPending();

      expect(existente.slug, antesSlug);
      expect(await SyncQueueService.activePendingCount(), 1);
      final err = await SyncQueueService.lastProdutoSyncErrorForEntity(
        lojaId: lojaId,
        entityKey: existente.key as int,
      );
      expect(err, isNotNull);
      expect(err!.toLowerCase(), contains('recuper'));
    });

    test('6. esgotamento de 5 candidatos → sem push, fila preservada', () async {
      final nome = 'Esgota Tentativas';
      final base = ProdutoEstoqueDocIdService.slugCanonicoParaLoja(
        lojaId: lojaId,
        nome: nome,
      );
      await tombstone(base);
      for (var n = 2; n <= ProdutoImportSyncPrepService.maxTentativasColisao; n++) {
        await tombstone('$base-$n');
      }

      final p = await importarOffline(nome);
      final slugAntes = p.slug;
      final qtdAntes = p.quantidade;

      await SyncQueueService.processPending();

      expect(p.slug, slugAntes);
      expect(p.quantidade, qtdAntes);
      expect(await SyncQueueService.activePendingCount(), 1);

      final docs = await firestore
          .collection('lojas')
          .doc(lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .get();
      expect(docs.docs, isEmpty);
    });

    test('7. docId remoto seguro em todos os cenários', () async {
      final ids = <String>[];
      for (final nome in ['Alpha', 'Beta', 'Gama']) {
        final p = await importarOffline(nome);
        ids.add(p.slug);
        expect(p.slug.startsWith(ProdutoImportDocIdHelper.importLocalIdPrefix),
            isTrue);
      }
      for (final id in ids) {
        expect(ProdutoFirestoreDocIdValidator.isProdutoIdSeguro(id), isTrue);
        expect(id.contains('/'), isFalse);
        expect(id.contains('://'), isFalse);
      }
      expect(ids.toSet().length, ids.length);
    });
  });
}
