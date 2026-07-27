// L7 — combo stock versioning (ficheiro dedicado para evitar interferência Hive).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loja = 'loja-r83-l7';
const _compA = 'comp-a-l7';
const _compB = 'comp-b-l7';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveRoot;
  late FakeFirebaseFirestore fakeDb;
  late Box<Produto> box;

  setUpAll(() async {
    hiveRoot = await Directory.systemTemp.createTemp('hive_l7_only_');
    Hive.init(hiveRoot.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await hiveRoot.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _loja;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    fakeDb = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = fakeDb;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = fakeDb;
    final boxName = 'l7_${DateTime.now().microsecondsSinceEpoch}';
    box = await Hive.openBox<Produto>(boxName);

    for (final entry in [(_compA, 10), (_compB, 10)]) {
      final id = entry.$1;
      final qty = entry.$2;
      final data = {
        'nome': id,
        'slug': id,
        'quantidade': qty,
        'variacoes': {'sem-tamanho': {'sem-cor': qty}},
        kProdutoStockRevisionField: 0,
      };
      await fakeDb
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .set(data);
      final p = Produto.vazio()
        ..nome = id
        ..idFirebase = id
        ..slug = id
        ..lojaId = _loja
        ..quantidade = qty
        ..variacoes = {'sem-tamanho': {'sem-cor': qty}};
      await box.add(p);
    }
  });

  tearDown(() async {
    EstoqueTransactionService.debugClearOverrides();
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    await box.close();
  });

  test('L7_COMBO_STOCK_VERSIONING_GREEN baixa componentes com revision', () async {
    final opId = 'l7-combo-${DateTime.now().microsecondsSinceEpoch}';

    final results =
        await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
      lojaId: _loja,
      itens: [
        {
          'productId': _compA,
          'quantidade': 2,
          'tamanho': 'sem-tamanho',
          'cor': 'sem-cor',
        },
        {
          'productId': _compB,
          'quantidade': 2,
          'tamanho': 'sem-tamanho',
          'cor': 'sem-cor',
        },
      ],
      operationId: opId,
    );

    expect(results.baixaAplicadaNestaExecucao, isTrue);
    expect(results.transactionResults, hasLength(2));
    for (final r in results.transactionResults) {
      expect(r.newStockRevision, 1);
      expect(r.stockOperationId, opId);
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: box,
        lojaId: _loja,
        result: r,
      );
    }

    Produto? find(String id) {
      for (final p in box.values) {
        if (p.idFirebase == id) return p;
      }
      return null;
    }

    expect(find(_compA)?.quantidade, 8);
    expect(find(_compB)?.quantidade, 8);
    expect(hasPendingStockMutation(find(_compA)!), isTrue);
  });
}
