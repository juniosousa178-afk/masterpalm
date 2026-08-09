// RECOVERY.2.3 — contrato syncProdutoComStatus + stock metadata (FakeFirestore).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loja = 'loja-r23-sync';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_r23_');
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    EstoqueTransactionService.debugFirestoreOverride = firestore;
  });

  tearDown(() {
    ProdutosFirestoreService.debugFirestoreOverride = null;
    EstoqueTransactionService.debugClearOverrides();
  });

  test('unchanged product repeated sync returns confirmado', () async {
    const id = 'prod-r23-unchanged';
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .set({
      'nome': 'Igual',
      'quantidade': 4,
      'slug': id,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'stockRevision': 0,
    });

    final p = Produto.vazio()
      ..nome = 'Igual'
      ..idFirebase = id
      ..slug = id
      ..lojaId = _loja
      ..quantidade = 4
      ..precoFinal = 10
      ..updatedAt = DateTime(2026, 7, 1);
    final box = await Hive.openBox<Produto>('r23_u_${DateTime.now().microsecondsSinceEpoch}');
    await box.add(p);

    final s1 = await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _loja,
      bumpHiveTimestamp: false,
      enqueueOnFailure: false,
    );
    final s2 = await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _loja,
      bumpHiveTimestamp: false,
      enqueueOnFailure: false,
    );
    expect(s1, ProdutoSyncRemotoStatus.confirmado);
    expect(s2, ProdutoSyncRemotoStatus.semMudancas);
    await box.close();
  });

  test('legacy remote sem stock metadata não bloqueia push cadastro', () async {
    const id = 'prod-r23-legacy';
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .set({'nome': 'Legado', 'slug': id});

    final p = Produto.vazio()
      ..nome = 'Legado edit'
      ..idFirebase = id
      ..slug = id
      ..lojaId = _loja
      ..quantidade = 2
      ..descricao = 'nova'
      ..precoFinal = 11
      ..updatedAt = DateTime(2026, 8, 1);
    final box = await Hive.openBox<Produto>('r23_l_${DateTime.now().microsecondsSinceEpoch}');
    await box.add(p);

    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _loja,
      bumpHiveTimestamp: true,
      enqueueOnFailure: false,
      forcePushFromCadastro: true,
    );
    expect(status, ProdutoSyncRemotoStatus.confirmado);
    final doc = await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .get();
    expect(doc.data()?['descricao'], 'nova');
    await box.close();
  });

  test('non-stock edit não avança stockRevision', () async {
    const id = 'prod-r23-nonstock';
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .set({
      'nome': 'N',
      'quantidade': 5,
      'stockRevision': 3,
      'slug': id,
      'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 1)),
    });

    final p = Produto.vazio()
      ..nome = 'Novo nome'
      ..idFirebase = id
      ..slug = id
      ..lojaId = _loja
      ..quantidade = 5
      ..stockRevision = 3
      ..precoFinal = 99
      ..updatedAt = DateTime(2026, 8, 1);
    final box = await Hive.openBox<Produto>('r23_n_${DateTime.now().microsecondsSinceEpoch}');
    await box.add(p);

    await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _loja,
      bumpHiveTimestamp: true,
      enqueueOnFailure: false,
      forcePushFromCadastro: true,
    );
    final doc = await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(id)
        .get();
    expect(doc.data()?['stockRevision'], 3);
    await box.close();
  });

  test('stale remote product updatedAt bloqueia push local stale', () {
    final local = Produto.vazio()
      ..quantidade = 3
      ..updatedAt = DateTime(2026, 1, 1);
    final skip = ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
      local: local,
      existingData: {
        'quantidade': 10,
        'updatedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
        'stockRevision': 0,
      },
      bumpHiveTimestamp: false,
      updatedAtBeforeBump: local.updatedAt,
    );
    expect(skip, isTrue);
  });

  test('newer remote stock revision bloqueia push local stale grade', () {
    final local = Produto.vazio()
      ..quantidade = 10
      ..stockRevision = 0;
    expect(
      evaluatePushStockSkip(
        local: local,
        existingData: {
          'quantidade': 7,
          'stockRevision': 5,
        },
      ),
      isTrue,
    );
  });
}
