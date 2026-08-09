// RECOVERY.2.2 — gates explícitos (sem produção; FakeFirestore + Hive).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_access_guard.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loja = 'loja-recovery22';
const _pid = 'prod-recovery22-simple';
const _tamA = 'var-a';
const _tamB = 'var-b';

Future<void> _seedSimple(FakeFirebaseFirestore db, {int qty = 10}) async {
  await db
      .collection('lojas')
      .doc(_loja)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(_pid)
      .set({
    'nome': 'Prod R22',
    'quantidade': qty,
    'slug': _pid,
    'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'stockRevision': 0,
  });
}

Future<void> _seedMultiVar(FakeFirebaseFirestore db) async {
  await db
      .collection('lojas')
      .doc(_loja)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(_pid)
      .set({
    'nome': 'Prod R22 MV',
    'quantidade': 12,
    'slug': _pid,
    'variacoes': {
      _tamA: {'sem-cor': 5},
      _tamB: {'sem-cor': 7},
    },
    'estoquePorTamanho': {_tamA: 5, _tamB: 7},
    'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'stockRevision': 0,
  });
}

Future<Box<Produto>> _openBox() async {
  return Hive.openBox<Produto>('r22_${DateTime.now().microsecondsSinceEpoch}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_r22_');
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
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    FirestoreAccessGuard.forbidAccess = false;
  });

  tearDown(() {
    EstoqueTransactionService.debugClearOverrides();
    ProdutosFirestoreService.debugFirestoreOverride = null;
  });

  test('NEWER_REMOTE_STOCK revision 11 aceita stock remoto 7', () {
    final local = Produto.vazio()
      ..quantidade = 8
      ..stockRevision = 10
      ..variacoes = {_tamA: {'sem-cor': 3}, _tamB: {'sem-cor': 4}};
    final remote = {
      'quantidade': 7,
      'variacoes': {
        _tamA: {'sem-cor': 2},
        _tamB: {'sem-cor': 3},
      },
      kProdutoStockRevisionField: 11,
      kProdutoStockOperationIdField: 'op-remote-newer-r22',
    };
    final decision = evaluatePullStockMergeByRevision(
      local: local,
      remoteData: remote,
    );
    expect(decision, PullStockMergeDecision.acceptRemote);
  });

  test('STALE_REMOTE snapshot bloqueado quando local revision maior', () {
    final local = Produto.vazio()
      ..quantidade = 8
      ..stockRevision = 10
      ..variacoes = {_tamA: {'sem-cor': 3}, _tamB: {'sem-cor': 4}};
    final remote = {
      'quantidade': 10,
      'variacoes': {
        _tamA: {'sem-cor': 5},
        _tamB: {'sem-cor': 7},
      },
      kProdutoStockRevisionField: 0,
    };
    expect(
      ProdutosFirestoreService.shouldPreserveLocalStockOnRemoteRegression(
        local: local,
        remoteData: remote,
      ),
      isTrue,
    );
  });

  test('LEGITIMATE_STOCK_REVERSAL devolução após venda', () async {
    await _seedSimple(firestore, qty: 10);
    final box = await _openBox();
    await box.add(
      Produto.vazio()
        ..nome = 'Prod R22'
        ..idFirebase = _pid
        ..slug = _pid
        ..lojaId = _loja
        ..quantidade = 10
        ..precoFinal = 50
        ..updatedAt = DateTime(2026, 1, 1)
        ..stockRevision = 0,
    );

    final baixa = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: _loja,
      itens: [
        {'productId': _pid, 'quantidade': 2},
      ],
    );
    for (final r in baixa) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: _loja,
        result: r,
      );
    }
    expect(box.values.first.quantidade, 8);
    expect(box.values.first.stockRevision, greaterThan(0));

    final devolucao = await EstoqueTransactionService.devolverEstoqueTransactionBatch(
      lojaId: _loja,
      itens: [
        {'productId': _pid, 'quantidade': 2},
      ],
      vendaIdParaIdempotencia: 'venda-r22-estorno',
    );
    for (final r in devolucao) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: _loja,
        result: r,
      );
    }
    expect(box.values.first.quantidade, 10);

    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'quantidade': 8,
      'stockRevision': 0,
      'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
    }, SetOptions(merge: true));
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _loja,
      produtosBox: box,
    );
    expect(box.values.first.quantidade, 10);
    await box.close();
  });

  test('MULTI_LINE_SAME_PRODUCT duas linhas mesmo produto', () async {
    await _seedSimple(firestore, qty: 10);
    final box = await _openBox();
    await box.add(
      Produto.vazio()
        ..nome = 'Prod R22'
        ..idFirebase = _pid
        ..slug = _pid
        ..lojaId = _loja
        ..quantidade = 10
        ..precoFinal = 50
        ..stockRevision = 0,
    );

    final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: _loja,
      itens: [
        {'productId': _pid, 'quantidade': 1},
        {'productId': _pid, 'quantidade': 2},
      ],
    );
    for (final r in results) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: _loja,
        result: r,
      );
    }
    expect(box.values.first.quantidade, 7);
    await box.close();
  });

  test('MULTI_VARIATION stale protection após baixa', () async {
    await _seedMultiVar(firestore);
    final box = await _openBox();
    await box.add(
      Produto.vazio()
        ..nome = 'Prod R22 MV'
        ..idFirebase = _pid
        ..slug = _pid
        ..lojaId = _loja
        ..quantidade = 12
        ..variacoes = {
          _tamA: {'sem-cor': 5},
          _tamB: {'sem-cor': 7},
        }
        ..estoquePorTamanho = {_tamA: 5, _tamB: 7}
        ..stockRevision = 0,
    );

    final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
      lojaId: _loja,
      itens: [
        {'productId': _pid, 'quantidade': 2, 'tamanho': _tamA},
        {'productId': _pid, 'quantidade': 3, 'tamanho': _tamB},
      ],
    );
    for (final r in results) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: _loja,
        result: r,
      );
    }
    final p = box.values.first;
    expect((p.variacoes?[_tamA] as Map?)?['sem-cor'], 3);
    expect((p.variacoes?[_tamB] as Map?)?['sem-cor'], 4);

    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'quantidade': 12,
      'variacoes': {
        _tamA: {'sem-cor': 5},
        _tamB: {'sem-cor': 7},
      },
      'stockRevision': 0,
      'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
    }, SetOptions(merge: true));
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _loja,
      produtosBox: box,
    );
    expect((p.variacoes?[_tamA] as Map?)?['sem-cor'], 3);
    expect((p.variacoes?[_tamB] as Map?)?['sem-cor'], 4);
    await box.close();
  });

  test('CREATE codigoBarras com zeros no Firestore', () async {
    final box = await _openBox();
    final p = Produto.vazio()
      ..nome = 'Novo Codigo'
      ..lojaId = _loja
      ..idFirebase = 'prod-create-code'
      ..slug = 'prod-create-code'
      ..codigoBarras = '000123'
      ..quantidade = 1
      ..precoFinal = 10;
    await box.add(p);

    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _loja,
      bumpHiveTimestamp: false,
      enqueueOnFailure: false,
      forcePushFromCadastro: true,
    );
    expect(status, isNot(ProdutoSyncRemotoStatus.lojaInvalida));

    final doc = await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-create-code')
        .get();
    expect(doc.data()?['codigoBarras'], '000123');
    await box.close();
  });

  test('EDIT codigoBarras cross pull', () async {
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-edit-code')
        .set({
      'nome': 'Edit Code',
      'quantidade': 5,
      'slug': 'prod-edit-code',
      'codigoBarras': '111111',
      'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'stockRevision': 0,
    });

    final boxA = await _openBox();
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _loja,
      produtosBox: boxA,
    );
    final local = boxA.values.first;
    local.codigoBarras = '222222';
    local.updatedAt = DateTime(2026, 8, 1);
    await ProdutosFirestoreService.syncProdutoComStatus(
      local,
      lojaId: _loja,
      bumpHiveTimestamp: true,
      enqueueOnFailure: false,
      forcePushFromCadastro: true,
    );

    final remoteDoc = await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-edit-code')
        .get();
    expect(remoteDoc.data()?['codigoBarras'], '222222');

    final boxB = await _openBox();
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _loja,
      produtosBox: boxB,
    );
    expect(boxB.values.first.codigoBarras, '222222');
    await boxA.close();
    await boxB.close();
  });

  test('PARTIAL update preserva codigoBarras', () async {
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-partial')
        .set({
      'nome': 'Partial',
      'quantidade': 5,
      'preco': 50.0,
      'slug': 'prod-partial',
      'codigoBarras': '789123',
      'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'stockRevision': 0,
    });
    final box = await _openBox();
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _loja,
      produtosBox: box,
    );
    final p = box.values.first;
    p.precoFinal = 99;
    p.quantidade = 6;
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
        .doc('prod-partial')
        .get();
    expect(doc.data()?['codigoBarras'], '789123');
    await box.close();
  });

  test('REPEATED_SYNC preserva codigoBarras após pull/push', () async {
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-repeat-sync')
        .set({
      'nome': 'Repeat',
      'quantidade': 2,
      'slug': 'prod-repeat-sync',
      'codigoBarras': 'SYNC-CODE-99',
      'updatedAt': Timestamp.fromDate(DateTime(2026, 7, 1)),
      'stockRevision': 0,
    });
    final box = await _openBox();
    for (var i = 0; i < 2; i++) {
      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _loja,
        produtosBox: box,
      );
      final p = box.values.first;
      await ProdutosFirestoreService.syncProdutoComStatus(
        p,
        lojaId: _loja,
        bumpHiveTimestamp: true,
        enqueueOnFailure: false,
        forcePushFromCadastro: false,
      );
    }
    final doc = await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-repeat-sync')
        .get();
    expect(doc.data()?['codigoBarras'], 'SYNC-CODE-99');
    await box.close();
  });

  test('LEGACY sem codigoBarras carrega', () async {
    await firestore
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc('prod-legacy')
        .set({
      'nome': 'Legacy',
      'quantidade': 1,
      'slug': 'prod-legacy',
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    final box = await _openBox();
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _loja,
      produtosBox: box,
    );
    expect(box.values.first.codigoBarras, '');
    await box.close();
  });
}
