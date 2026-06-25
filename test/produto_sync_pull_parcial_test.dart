// Pull parcial: pendente local não bloqueia download de remoto sem conflito.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_access_guard.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lojaA = 'mirjoias';
  const lojaB = 'mariaisaabel42';
  late String hivePath;
  late FakeFirebaseFirestore fake;
  late Box<Produto> boxA;
  late Box<Produto> boxB;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_pull_parcial_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  tearDownAll(() async {
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  Future<void> seedRemoto(String lojaId, String docId, String nome) async {
    await fake
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(docId)
        .set({
      'nome': nome,
      'quantidade': 7,
      'preco': 20,
      'slug': docId,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fake = FakeFirebaseFirestore();
    FirestoreAccessGuard.resetForTests();
    ProdutosFirestoreService.debugFirestoreOverride = fake;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = fake;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    ProdutosFirestoreService.debugForbidFirestoreAccess = false;

    await SyncQueueService.init();
    await SyncQueueService.clearQueue();

    final s = DateTime.now().microsecondsSinceEpoch;
    boxA = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaA) + '_$s');
    boxB = await Hive.openBox<Produto>(HiveBoxNames.produtos(lojaB) + '_$s');
  });

  tearDown(() async {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    FirestoreAccessGuard.resetForTests();
    await SyncQueueService.clearQueue();
    await boxA.close();
    await boxB.close();
  });

  test('P1 pendente não é sobrescrito; P2 remoto é baixado', () async {
    await seedRemoto(lojaA, 'remoto-p1', 'Prod P1 Remoto');
    await seedRemoto(lojaA, 'remoto-p2', 'Prod P2 Remoto');

    final p1 = Produto(
      nome: 'Prod P1 Local',
      slug: 'local-p1-slug',
      idFirebase: 'remoto-p1',
      custoReal: 1,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 15,
      quantidade: 99,
      precoUnitario: 15,
      categoria: 'C',
      dataEntrada: DateTime.now(),
      lojaId: lojaA,
      updatedAt: DateTime(2026, 6, 1),
    );
    await boxA.add(p1);
    final keyP1 = p1.key as int;

    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaA,
      boxName: boxA.name,
      entityKey: keyP1,
      lastError: 'identificador-excluido (tombstone)',
    );

    final n = await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: lojaA,
      produtosBox: boxA,
    );
    expect(n, greaterThan(0));

    final localP1 = boxA.get(keyP1)!;
    expect(localP1.quantidade, 99);
    expect(localP1.precoFinal, 15);

    final p2Matches = boxA.values.where((p) => p.idFirebase == 'remoto-p2');
    expect(p2Matches.length, 1);
    expect(p2Matches.first.quantidade, 7);

    final pull2 = await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: lojaA,
      produtosBox: boxA,
    );
    expect(p2Matches.length, 1);
    expect(
      boxA.values.where((p) => p.idFirebase == 'remoto-p2').length,
      1,
    );
    expect(pull2, greaterThanOrEqualTo(0));
  });

  test('fila da loja B não impede pull da loja A', () async {
    await seedRemoto(lojaA, 'remoto-a-only', 'Só Loja A');

    final pb = Produto(
      nome: 'Prod B',
      slug: 'b-local',
      custoReal: 1,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 5,
      quantidade: 1,
      precoUnitario: 5,
      categoria: 'C',
      dataEntrada: DateTime.now(),
      lojaId: lojaB,
    );
    await boxB.add(pb);
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaB,
      boxName: boxB.name,
      entityKey: pb.key as int,
    );

    final n = await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: lojaA,
      produtosBox: boxA,
    );
    expect(n, 1);
    expect(boxA.values.where((p) => p.lojaId == lojaA).length, 1);
    expect(boxB.length, 1);
  });

  test('processamento com escopo ignora fila de outra loja', () async {
    final pa = Produto(
      nome: 'A',
      slug: 'a1',
      custoReal: 1,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 5,
      quantidade: 1,
      precoUnitario: 5,
      categoria: 'C',
      dataEntrada: DateTime.now(),
      lojaId: lojaA,
    );
    final pb = Produto(
      nome: 'B',
      slug: 'b1',
      custoReal: 1,
      frete: 0,
      gastosFixos: 0,
      gastosVariaveis: 0,
      precoSugerido: 0,
      precoFinal: 5,
      quantidade: 1,
      precoUnitario: 5,
      categoria: 'C',
      dataEntrada: DateTime.now(),
      lojaId: lojaB,
    );
    await boxA.add(pa);
    await boxB.add(pb);

    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaA,
      boxName: boxA.name,
      entityKey: pa.key as int,
      scheduleProcess: false,
    );
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaB,
      boxName: boxB.name,
      entityKey: pb.key as int,
      scheduleProcess: false,
    );

    ProdutosFirestoreService.debugForbidFirestoreAccess = true;
    await SyncQueueService.processPending(scopeLojaId: lojaA);
    final restantes = await SyncQueueService.listDiagnosticEntries();
    expect(restantes.length, 2);
    expect(restantes.where((e) => e.lojaId == lojaB).length, 1);
    expect(restantes.where((e) => e.lojaId == lojaA).length, 1);
  });

  test('dead-letter na loja B não implica pendência na loja A', () async {
    await SyncQueueService.enqueue(
      type: SyncOperationType.upsertProduto,
      lojaId: lojaB,
      boxName: boxB.name,
      entityKey: 0,
      lastError: 'identificador-excluido (tombstone)',
      scheduleProcess: false,
    );

    expect(
      await SyncQueueService.hasPendingProdutoSyncForStore(lojaId: lojaB),
      isTrue,
    );
    expect(
      await SyncQueueService.hasPendingProdutoSyncForStore(lojaId: lojaA),
      isFalse,
    );
  });
}
