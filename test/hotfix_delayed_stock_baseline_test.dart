// HOTFIX.1 — reversão tardia de estoque na baseline 33137cf (write + pull + push).
// Sem dependências de LojaAtivaResolver / sync queue WIP.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-hotfix-delayed-stock';
const _pid = 'prod-hotfix-ds';
const _tamA = 'var-a';
const _tamB = 'var-b';
const _qA0 = 5;
const _qB0 = 7;
const _total0 = _qA0 + _qB0;

Future<void> _seedFirestore(FakeFirebaseFirestore db) async {
  await db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(_pid)
      .set({
    'nome': 'Produto DS',
    'quantidade': _total0,
    'slug': _pid,
    'variacoes': {
      _tamA: {'sem-cor': _qA0},
      _tamB: {'sem-cor': _qB0},
    },
    'estoquePorTamanho': {_tamA: _qA0, _tamB: _qB0},
    'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'stockRevision': 0,
  });
}

Future<Box<Produto>> _seedHive(String hivePath) async {
  final box = await Hive.openBox<Produto>('prod_ds_${DateTime.now().microsecondsSinceEpoch}');
  await box.add(
    Produto.vazio()
        ..nome = 'Produto DS'
        ..idFirebase = _pid
        ..slug = _pid
        ..lojaId = _lojaId
        ..quantidade = _total0
        ..precoFinal = 50
        ..custoEditadoNoCadastro = true
        ..variacoes = {
          _tamA: {'sem-cor': _qA0},
          _tamB: {'sem-cor': _qB0},
        }
        ..estoquePorTamanho = {_tamA: _qA0, _tamB: _qB0}
        ..updatedAt = DateTime(2026, 1, 1)
        ..stockRevision = 0,
  );
  return box;
}

Future<void> _baixaVendaMultiVar(Box<Produto> box) async {
  final results = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
    lojaId: _lojaId,
    itens: [
      {
        'productId': _pid,
        'quantidade': 2,
        'tamanho': _tamA,
      },
      {
        'productId': _pid,
        'quantidade': 3,
        'tamanho': _tamB,
      },
    ],
  );
  for (final r in results) {
    await EstoqueTransactionService.atualizarHiveAposTransacao(
      produtosBox: box,
      lojaId: _lojaId,
      result: r,
    );
  }
}

void _expectGrade(Box<Produto> box, int qA, int qB, int total) {
  final p = box.values.firstWhere((x) => x.idFirebase == _pid);
  expect(p.quantidade, total);
  expect((p.variacoes?[_tamA] as Map?)?['sem-cor'], qA);
  expect((p.variacoes?[_tamB] as Map?)?['sem-cor'], qB);
  expect(p.stockRevision, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_hotfix_ds_');
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
  });

  tearDown(() {
    EstoqueTransactionService.debugClearOverrides();
    ProdutosFirestoreService.debugFirestoreOverride = null;
  });

  test('venda multi-variação baixa e persiste no Hive', () async {
    await _seedFirestore(firestore);
    final box = await _seedHive(hivePath);
    await _baixaVendaMultiVar(box);
    _expectGrade(box, 3, 4, 7);
    final remoto = await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .get();
    expect((remoto.data()?['quantidade'] as num?)?.toInt(), 7);
    await box.close();
  });

  test('pull com snapshot remoto stale não restaura grade local', () async {
    await _seedFirestore(firestore);
    final box = await _seedHive(hivePath);
    await _baixaVendaMultiVar(box);
    _expectGrade(box, 3, 4, 7);

    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'nome': 'Produto DS',
      'quantidade': _total0,
      'slug': _pid,
      'variacoes': {
        _tamA: {'sem-cor': _qA0},
        _tamB: {'sem-cor': _qB0},
      },
      'estoquePorTamanho': {_tamA: _qA0, _tamB: _qB0},
      'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'stockRevision': 0,
    }, SetOptions(merge: true));

    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _lojaId,
      produtosBox: box,
    );
    _expectGrade(box, 3, 4, 7);
    await box.close();
  });

  test('push stale em memória não restaura remoto', () async {
    await _seedFirestore(firestore);
    final box = await _seedHive(hivePath);
    await _baixaVendaMultiVar(box);
    _expectGrade(box, 3, 4, 7);

    final p = box.values.firstWhere((x) => x.idFirebase == _pid);
    p.quantidade = _total0;
    p.variacoes = {
      _tamA: {'sem-cor': _qA0},
      _tamB: {'sem-cor': _qB0},
    };
    p.estoquePorTamanho = {_tamA: _qA0, _tamB: _qB0};
    p.stockRevision = 0;
    p.pendingStockOperationId = null;
    p.pendingStockBaseRevision = null;
    p.updatedAt = DateTime(2020, 1, 1);

    final status = await ProdutosFirestoreService.syncProdutoComStatus(
      p,
      lojaId: _lojaId,
      bumpHiveTimestamp: true,
      enqueueOnFailure: false,
      writeOrigin: 'test.hotfix_stale_push',
    );
    expect(status, ProdutoSyncRemotoStatus.semMudancas);

    final remoto = await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .get();
    expect((remoto.data()?['quantidade'] as num?)?.toInt(), 7);
    await box.close();
  });

  test('remote newer legítimo é aceito no pull', () async {
    await _seedFirestore(firestore);
    final box = await _seedHive(hivePath);
    await _baixaVendaMultiVar(box);

    final local = box.values.firstWhere((p) => p.idFirebase == _pid);
    final confirmOp = local.pendingStockOperationId ?? 'remote-newer-op';

    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'nome': 'Produto DS',
      'quantidade': 2,
      'slug': _pid,
      'variacoes': {
        _tamA: {'sem-cor': 1},
        _tamB: {'sem-cor': 1},
      },
      'estoquePorTamanho': {_tamA: 1, _tamB: 1},
      'updatedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
      'stockRevision': 5,
      'stockOperationId': confirmOp,
      'stockUpdatedAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
    }, SetOptions(merge: true));

    final pBeforePull = box.values.firstWhere((x) => x.idFirebase == _pid);
    pBeforePull.updatedAt = DateTime(2020, 1, 1);
    await pBeforePull.save();

    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _lojaId,
      produtosBox: box,
    );
    final p = box.values.firstWhere((x) => x.idFirebase == _pid);
    expect(p.quantidade, 2);
    expect(p.stockRevision, 5);
    await box.close();
  });

  test('gate pull stale sem revision local ainda bloqueia regressão de grade', () {
    final local = Produto.vazio()
      ..quantidade = 8
      ..stockRevision = 2
      ..pendingStockOperationId = 'op-local'
      ..pendingStockBaseRevision = 1
      ..variacoes = {_tamA: {'sem-cor': 3}, _tamB: {'sem-cor': 4}};
    final remote = {
      'quantidade': _total0,
      'variacoes': {
        _tamA: {'sem-cor': _qA0},
        _tamB: {'sem-cor': _qB0},
      },
      'stockRevision': 0,
    };
    expect(
      ProdutosFirestoreService.shouldPreserveLocalStockOnRemoteRegression(
        local: local,
        remoteData: remote,
      ),
      isTrue,
    );
  });

  test('repeated sync após stale não altera grade', () async {
    await _seedFirestore(firestore);
    final box = await _seedHive(hivePath);
    await _baixaVendaMultiVar(box);
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'quantidade': _total0,
      'variacoes': {
        _tamA: {'sem-cor': _qA0},
        _tamB: {'sem-cor': _qB0},
      },
      'estoquePorTamanho': {_tamA: _qA0, _tamB: _qB0},
      'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'stockRevision': 0,
    }, SetOptions(merge: true));
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _lojaId,
      produtosBox: box,
    );
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _lojaId,
      produtosBox: box,
    );
    _expectGrade(box, 3, 4, 7);
    await box.close();
  });

  test('reload hive mantém estoque após pull stale', () async {
    await _seedFirestore(firestore);
    final box = await _seedHive(hivePath);
    await _baixaVendaMultiVar(box);
    final boxName = box.name;
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'quantidade': _total0,
      'variacoes': {
        _tamA: {'sem-cor': _qA0},
        _tamB: {'sem-cor': _qB0},
      },
      'estoquePorTamanho': {_tamA: _qA0, _tamB: _qB0},
      'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
      'stockRevision': 0,
    }, SetOptions(merge: true));
    await ProdutosFirestoreService.syncFirestoreToHive(
      lojaId: _lojaId,
      produtosBox: box,
    );
    await box.close();
    final reopened = await Hive.openBox<Produto>(boxName);
    _expectGrade(reopened, 3, 4, 7);
    await reopened.close();
  });
}
