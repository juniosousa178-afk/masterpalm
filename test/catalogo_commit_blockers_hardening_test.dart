import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/screens/public_catalog/catalog_estoque_helper.dart';
import 'package:master_palm/services/catalog_publish_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// fake_cloud_firestore 3.1.0 does not retry conflicts. This test double buffers
// writes and validates the read set before commit, modelling Firestore retries.
// It runs the real publisher/decrement callbacks; no publisher logic is copied.
class _RetryingFirestore extends FakeFirebaseFirestore {
  Future<void> Function()? beforeCommit;
  int retries = 0;

  @override
  Future<T> runTransaction<T>(TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final tx = _BufferedTransaction();
      final result = await handler(tx);
      final pause = beforeCommit;
      beforeCommit = null;
      if (pause != null) await pause();
      if (!await tx.readsUnchanged()) {
        retries++;
        continue;
      }
      await tx.commit();
      return result;
    }
    throw StateError('transaction retry limit');
  }
}

class _BufferedTransaction implements Transaction {
  final _reads = <String, String>{};
  final _refs = <String, DocumentReference>{};
  final _writes = <Future<void> Function()>[];

  String _encode(DocumentSnapshot snap) =>
      jsonEncode({'exists': snap.exists, 'data': snap.data()},
          toEncodable: (v) => v is Timestamp
              ? [v.seconds, v.nanoseconds]
              : v.toString());

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> ref) async {
    if (_writes.isNotEmpty) throw StateError('read after write');
    final snap = await ref.get();
    _reads[ref.path] = _encode(snap);
    _refs[ref.path] = ref;
    return snap;
  }

  Future<bool> readsUnchanged() async {
    for (final e in _reads.entries) {
      if (_encode(await _refs[e.key]!.get()) != e.value) return false;
    }
    return true;
  }

  Future<void> commit() async {
    for (final write in _writes) {
      await write();
    }
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    _writes.add(() => ref.set(data, options));
    return this;
  }

  @override
  Transaction delete(DocumentReference ref) {
    _writes.add(ref.delete);
    return this;
  }

  @override
  Transaction update(DocumentReference ref, Map<String, dynamic> data) {
    _writes.add(() => ref.update(data));
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const loja = 'hardening-local';
  const pid = 'produto';
  late _RetryingFirestore db;

  DocumentReference<Map<String, dynamic>> doc(String col) =>
      db.collection('lojas').doc(loja).collection(col).doc(pid);

  Future<void> seed(int qtd, {bool variable = false}) async {
    await doc('draft_produtos').set({
      'id': pid, 'tipoProduto': 'simples', 'publicar': true, 'ativo': true,
      'quantidade': qtd, 'estoque_atual': qtd,
      'tamanhos': variable ? ['P'] : <String>[],
      'cores': variable ? ['Azul'] : <String>[],
      if (variable) 'variacoes': {'P': {'Azul': qtd}},
    });
    await doc('estoque_produtos').set({
      'nome': 'Produto', 'quantidade': qtd,
      if (variable) 'variacoes': {'P': {'Azul': qtd}},
      if (variable) 'estoquePorTamanho': {'P': qtd},
    });
  }

  Future<void> stock(int qtd) => doc('estoque_produtos').set({
    'quantidade': qtd, 'variacoes': {'P': {'Azul': qtd}},
    'estoquePorTamanho': {'P': qtd},
  }, SetOptions(merge: true));

  Future<void> publish() =>
      CatalogPublishService.promoteOne(pid, lojaIdOverride: loja);

  Future<int> visibleStock() async {
    final live = await doc('produtos').get();
    if (!live.exists) return 0;
    return CatalogEstoqueHelper.processStockFromFirestoreMap(
      live.data()!, isCombo: false).quantidadeTotal;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = _RetryingFirestore();
    CatalogPublishService.debugFirestoreOverride = db;
    EstoqueTransactionService.debugFirestoreOverride = db;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = db;
  });

  tearDown(() {
    CatalogPublishService.debugFirestoreOverride = null;
    EstoqueTransactionService.debugClearOverrides();
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
  });

  for (final shape in ['absent', 'null', 'empty']) {
    test('B1 simples positivo: $shape', () {
      final p = <String, dynamic>{
        'tipoProduto': 'simples', 'quantidade': 7,
        'tamanhos': <String>[], 'cores': <String>[],
        if (shape == 'null') 'variacoes': null,
        if (shape == 'empty') 'variacoes': <String, dynamic>{},
      };
      expect(CatalogEstoqueHelper.processStockFromFirestoreMap(
        p, isCombo: false).quantidadeTotal, 7);
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, '', ''), 7);
    });
  }

  test('B1 simples zero e mapa vazio permanece oculto', () {
    expect(CatalogEstoqueHelper.processStockFromFirestoreMap({
      'tipoProduto': 'simples', 'quantidade': 0, 'variacoes': {},
    }, isCombo: false).incluirNoCatalogo, isFalse);
  });

  test('B1 atributos persistidos preservam variavel com grade esvaziada', () {
    for (final marker in ['tamanhos', 'cores']) {
      expect(CatalogEstoqueHelper.processStockFromFirestoreMap({
        'tipoProduto': 'simples', 'quantidade': 9, 'estoque_atual': 9,
        'variacoes': {}, marker: ['P'],
      }, isCombo: false).incluirNoCatalogo, isFalse);
    }
  });

  test('B1 publicacao real normaliza e rele simples com saldo', () async {
    await seed(7);
    await publish();
    final live = (await doc('produtos').get()).data()!;
    expect(live['quantidade'], 7);
    expect(await visibleStock(), 7);
    expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(live, '', ''), 7);
  });

  test('B1 reposicao simples zero para cinco pelo publicador', () async {
    await seed(0);
    await publish();
    expect(await visibleStock(), 0);
    await doc('estoque_produtos').update({'quantidade': 5});
    await publish();
    expect(await visibleStock(), 5);
  });

  for (final alias in ['azul', 'AZUL', ' Azul ']) {
    test('B2 total nao herda agregado equivalente $alias', () {
      final p = <String, dynamic>{
        'variacoes': {'P': {'Azul': 0, 'Vermelho': 3}},
        'estoquePorCor': {alias: 9}, 'quantidade': 3,
      };
      expect(CatalogEstoqueHelper.processStockFromFirestoreMap(
        p, isCombo: false).quantidadeTotal, 3);
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, 'P', alias), 0);
      expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, 'P', 'Vermelho'), 3);
    });

    test('B2 baixa real resolve $alias e preserva Vermelho', () async {
      await seed(5, variable: true);
      await doc('estoque_produtos').update({
        'variacoes': {'P': {'Azul': 2, 'Vermelho': 3}},
        'estoquePorTamanho': {'P': 5},
      });
      await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: loja, produtoId: pid, quantidade: 1, tamanho: 'P', cor: alias);
      final data = (await doc('estoque_produtos').get()).data()!;
      expect(data['variacoes']['P']['Azul'], 1);
      expect(data['variacoes']['P']['Vermelho'], 3);
      await publish();
      expect(await visibleStock(), 4);
    });
  }

  test('B2 aliases duplicados nao duplicam total nem mudam display', () {
    final p = <String, dynamic>{
      'variacoes': {'P': {'Azul': 2, ' azul ': 2, 'Vermelho': 3}},
      'quantidade': 5,
    };
    final result = CatalogEstoqueHelper.processStockFromFirestoreMap(p, isCombo: false);
    expect(result.quantidadeTotal, 5);
    expect(result.variacoes!['P'].keys, contains('Azul'));
    expect(CatalogEstoqueHelper.estoqueDisponivelVariacao(p, 'P', 'AZUL'), 2);
  });

  test('B3 snapshot positivo antigo nao vence venda zero e sync novo', () async {
    await seed(1, variable: true);
    await publish();
    var interleaved = false;
    db.beforeCommit = () async {
      interleaved = true;
      await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: loja, produtoId: pid, quantidade: 1, tamanho: 'P', cor: 'Azul');
      await publish();
    };
    await publish();
    expect(interleaved, isTrue, reason: 'publisher must use the guarded transaction');
    expect(db.retries, greaterThan(0));
    expect((await doc('estoque_produtos').get()).data()!['quantidade'], 0);
    expect(await visibleStock(), 0);
  });

  test('B3 snapshot zero antigo nao apaga reposicao cinco', () async {
    await seed(0, variable: true);
    var interleaved = false;
    db.beforeCommit = () async {
      interleaved = true;
      await stock(5);
      await publish();
    };
    await publish();
    expect(interleaved, isTrue);
    expect(db.retries, greaterThan(0));
    expect(await visibleStock(), 5);
  });

  test('B3 dois syncs equivalentes sao idempotentes', () async {
    await seed(5, variable: true);
    await Future.wait([publish(), publish()]);
    expect(await visibleStock(), 5);
    expect((await doc('estoque_produtos').get()).data()!['quantidade'], 5);
    expect((await db.collection('lojas').doc(loja).collection('produtos').get()).docs.length, 1);
  });

  test('B3 venda idempotente concorrente nao duplica baixa nem ressuscita', () async {
    await seed(1, variable: true);
    const op = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
    Future<void> sale() async {
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: loja, operationId: op,
        itens: [{'productId': pid, 'quantidade': 1, 'tamanho': 'P', 'cor': 'Azul'}]);
    }
    db.beforeCommit = () async {
      await sale();
      await sale();
      await publish();
    };
    await publish();
    expect((await doc('estoque_produtos').get()).data()!['quantidade'], 0);
    expect(await visibleStock(), 0);
  });

  test('B3 promoteAll tambem protege o snapshot em concorrencia', () async {
    await seed(1, variable: true);
    db.beforeCommit = () async {
      await stock(0);
      await publish();
    };
    await CatalogPublishService.promoteAll(lojaIdOverride: loja);
    expect(db.retries, greaterThan(0));
    expect(await visibleStock(), 0);
  });

  test('mixed version: escrita legada direta ainda contorna guarda do app', () async {
    await seed(1, variable: true);
    await publish();
    final stale = (await doc('produtos').get()).data()!;
    await stock(0);
    await publish();
    expect(await visibleStock(), 0);
    // Reproduces the old publisher's final set; fake does not enforce rules.
    // Local firestore.rules permits this write for admin without stock revision.
    await doc('produtos').set(stale);
    expect(await visibleStock(), 1, reason: 'this is a documented release BLOCK');
  });
  test('B3 remocao atrasada de zero nao apaga reposicao mais nova', () async {
    await seed(0, variable: true);
    await doc('produtos').set({'id': pid, 'quantidade': 0});
    var interleaved = false;
    db.beforeCommit = () async {
      interleaved = true;
      await stock(5);
      await publish();
    };
    await EstoqueTransactionService.removerDoCatalogoSeEstoqueZerado(loja, [
      EstoqueTransactionResult(produtoId: pid, produtoNome: 'Produto',
        quantidadeDebitada: 1, quantidadeTotalAtualizada: 0),
    ]);
    expect(interleaved, isTrue);
    expect(db.retries, greaterThan(0));
    expect(await visibleStock(), 5);
  });

  test('B2 grade toda zerada com alias de cor nao entra na vitrine', () {
    final p = <String, dynamic>{
      'variacoes': {'P': {'Azul': 0}},
      'estoquePorCor': {' AZUL ': 9}, 'quantidade': 0,
    };
    expect(CatalogEstoqueHelper.processStockFromFirestoreMap(
      p, isCombo: false).incluirNoCatalogo, isFalse);
  });

  test('B3 segunda venda sem saldo e recusada sem estoque negativo', () async {
    await seed(1, variable: true);
    await EstoqueTransactionService.baixarEstoqueTransaction(
      lojaId: loja, produtoId: pid, quantidade: 1, tamanho: 'P', cor: 'Azul');
    await expectLater(EstoqueTransactionService.baixarEstoqueTransaction(
      lojaId: loja, produtoId: pid, quantidade: 1, tamanho: 'P', cor: 'Azul'),
      throwsException);
    expect((await doc('estoque_produtos').get()).data()!['quantidade'], 0);
    await publish();
    expect(await visibleStock(), 0);
  });

}
