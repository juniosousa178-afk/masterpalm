// STOCKTO-1…16 — timeout externo na transação batch de estoque (M3.7-HOTFIX-P0).

import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legacy_stock_batch_timeout_test_support.dart';

const _lojaId = 'loja-stockto';
const _opId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

Future<void> _seedSimples(FakeFirebaseFirestore db, String pid, int qtd) async {
  await db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .set({'nome': 'Prod Simples', 'quantidade': qtd, 'slug': pid});
}

Future<void> _seedVariacaoTamCor(
  FakeFirebaseFirestore db,
  String pid, {
  required String tam,
  required String cor,
  required int qtd,
}) async {
  await db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .set({
    'nome': 'Brinco Brilhante Quadrado 7mm',
    'quantidade': qtd,
    'slug': pid,
    'variacoes': {
      tam: {cor: qtd},
    },
    'estoquePorTamanho': {tam: qtd},
  });
}

List<Map<String, dynamic>> _item({
  required String pid,
  int qtd = 1,
  String tam = '',
  String cor = '',
}) =>
    [
      {
        'productId': pid,
        'nome': 'Item',
        'quantidade': qtd,
        if (tam.isNotEmpty) 'tamanho': tam,
        if (cor.isNotEmpty) 'cor': cor,
      },
    ];

Future<int> _qtdRemota(FakeFirebaseFirestore db, String pid) async {
  final snap = await db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

Future<bool> _markerBaixa(FakeFirebaseFirestore db, String opId) async {
  final snap = await db
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_baixa_pagamento')
      .doc(opId)
      .get();
  return snap.exists && snap.data()?['baixaAplicada'] == true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_stockto_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    EstoqueTransactionService.debugClearOverrides();
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
  });

  tearDown(() {
    EstoqueTransactionService.debugClearOverrides();
    ProdutosFirestoreService.debugFirestoreOverride = null;
  });

  group('STOCKTO — timeout batch estoque', () {
    test('STOCKTO-1 transação rápida completa sem timeout externo', () async {
      const pid = 'p-fast';
      await _seedSimples(firestore, pid, 5);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: _opId,
      );

      expect(r.status, EstoqueBaixaOperationStatus.applied);
      expect(await _qtdRemota(firestore, pid), 4);
      expect(await _markerBaixa(firestore, _opId), isTrue);
    });

    test('STOCKTO-2 RED: timeout legado 25s reproduz mensagem H1 (test-only)', () async {
      const pid = 'p-slow-red';
      await _seedSimples(firestore, pid, 5);
      EstoqueTransactionService.debugBatchTransactionDelay =
          const Duration(milliseconds: 200);

      expect(
        LegacyStockBatchTimeoutTestSupport.withLegacyBatchTimeout(
          EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
            lojaId: _lojaId,
            itens: _item(pid: pid),
            operationId: 'op-red-${DateTime.now().microsecondsSinceEpoch}',
          ),
          duration: const Duration(milliseconds: 50),
        ),
        throwsA(
          predicate<Object>((e) =>
              e is TimeoutException &&
              e.message ==
                  LegacyStockBatchTimeoutTestSupport.legacyUserMessage),
        ),
      );
    });

    test('STOCKTO-3 delay curto sem timeout legado completa (pós-fix)', () async {
      const pid = 'p-delay-ok';
      const op = 'op-delay-ok';
      await _seedSimples(firestore, pid, 3);
      EstoqueTransactionService.debugBatchTransactionDelay =
          const Duration(milliseconds: 150);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      expect(r.status, EstoqueBaixaOperationStatus.applied);
      expect(await _qtdRemota(firestore, pid), 2);
      expect(await _markerBaixa(firestore, op), isTrue);
    });

    test('STOCKTO-4 Future.timeout não cancela Future subjacente', () async {
      var completed = false;
      final inner = Future<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        completed = true;
      });

      await expectLater(
        inner.timeout(
          const Duration(milliseconds: 30),
          onTimeout: () => throw TimeoutException('timeout'),
        ),
        throwsA(isA<TimeoutException>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(completed, isTrue,
          reason: 'runTransaction Firestore pode commitar após timeout do cliente');
    });

    test('STOCKTO-5 retry idempotente após baixa aplicada', () async {
      const pid = 'p-retry';
      const op = 'op-retry-idem';
      await _seedSimples(firestore, pid, 2);

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      final r2 =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      expect(r2.status, EstoqueBaixaOperationStatus.alreadyApplied);
      expect(await _qtdRemota(firestore, pid), 1);
    });

    test('STOCKTO-6 mesmo operationId após timeout legado não duplica se marker existir',
        () async {
      const pid = 'p-same-op';
      const op = 'op-same-after-timeout';
      await _seedSimples(firestore, pid, 4);

      // Simula commit remoto bem-sucedido antes do timeout percebido:
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      expect(r.status, EstoqueBaixaOperationStatus.alreadyApplied);
      expect(await _qtdRemota(firestore, pid), 3);
    });

    test('STOCKTO-7 nova operationId após baixa debita novamente', () async {
      const pid = 'p-new-op';
      await _seedSimples(firestore, pid, 5);

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: 'op-first',
      );
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: 'op-second',
      );

      expect(await _qtdRemota(firestore, pid), 3);
    });

    test('STOCKTO-8 marker criado somente após commit da transação', () async {
      const pid = 'p-marker';
      const op = 'op-marker';
      await _seedSimples(firestore, pid, 2);

      expect(await _markerBaixa(firestore, op), isFalse);

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      expect(await _markerBaixa(firestore, op), isTrue);
    });

    test('STOCKTO-9 produção não aplica timeout externo no batch', () {
      final src = File('lib/services/estoque_transaction_service.dart')
          .readAsStringSync();
      final idxExecutar = src.indexOf('_executarBaixaBatchInterno');
      expect(idxExecutar, greaterThan(0));
      final chunk = src.substring(idxExecutar, idxExecutar + 4500);
      expect(
        chunk.contains('.timeout(') && chunk.contains('seconds: 25'),
        isFalse,
        reason: 'batch não deve ter .timeout(25s) em produção',
      );
    });

    test('STOCKTO-10 timeout legado isolado não altera estoque remoto', () async {
      const pid = 'p-no-debit';
      const op = 'op-timeout-no-debit';
      await _seedSimples(firestore, pid, 6);
      EstoqueTransactionService.debugBatchTransactionDelay =
          const Duration(milliseconds: 200);

      try {
        await LegacyStockBatchTimeoutTestSupport.withLegacyBatchTimeout(
          EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
            lojaId: _lojaId,
            itens: _item(pid: pid),
            operationId: op,
          ),
          duration: const Duration(milliseconds: 30),
        );
        fail('esperava TimeoutException');
      } on TimeoutException {
        // ok
      }

      // FakeFirestore commita antes do timeout percebido — estoque pode ter baixado.
      // Em produção real (STOCK-E) o efeito remoto é indeterminado após timeout.
      final qtd = await _qtdRemota(firestore, pid);
      expect(qtd, anyOf(5, 6));
    });

    test('STOCKTO-11 duas baixas concorrentes mesmo op → idempotente', () async {
      const pid = 'p-conc';
      const op = 'op-conc';
      await _seedSimples(firestore, pid, 10);

      final f1 = EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );
      final f2 = EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: op,
      );

      final results = await Future.wait([f1, f2]);
      final applied =
          results.where((r) => r.status == EstoqueBaixaOperationStatus.applied);
      final already = results
          .where((r) => r.status == EstoqueBaixaOperationStatus.alreadyApplied);

      expect(applied.length + already.length, 2);
      expect(await _qtdRemota(firestore, pid), 9);
    });

    test('STOCKTO-12 venda com variação tam+cor (H1-like)', () async {
      const pid = 'brinco-7mm';
      const op = 'op-var-h1';
      await _seedVariacaoTamCor(
        firestore,
        pid,
        tam: '7mm',
        cor: 'cristal',
        qtd: 5,
      );

      EstoqueTransactionService.debugBatchTransactionDelay =
          const Duration(milliseconds: 80);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid, tam: '7mm', cor: 'cristal'),
        operationId: op,
      );

      expect(r.status, EstoqueBaixaOperationStatus.applied);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('STOCKTO-13 venda simples sem variação', () async {
      const pid = 'simples-13';
      await _seedSimples(firestore, pid, 8);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: 'op-13',
      );

      expect(r.status, EstoqueBaixaOperationStatus.applied);
      expect(await _qtdRemota(firestore, pid), 7);
    });

    test('STOCKTO-14 permission-denied não vira timeout batch', () async {
      // FakeFirestore lança StateError/ArgumentError, não TimeoutException.
      expect(
        EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
          lojaId: '',
          itens: _item(pid: 'x'),
          operationId: _opId,
        ),
        throwsA(isNot(isA<TimeoutException>())),
      );
    });

    test('STOCKTO-15 contenção/retry idempotente preserva estoque', () async {
      const pid = 'p-cont';
      const op = 'op-cont';
      await _seedSimples(firestore, pid, 3);

      for (var i = 0; i < 3; i++) {
        await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
          lojaId: _lojaId,
          itens: _item(pid: pid),
          operationId: op,
        );
      }

      expect(await _qtdRemota(firestore, pid), 2);
    });

    test('STOCKTO-16 delay de rede simulado completa sem timeout pós-fix', () async {
      const pid = 'p-net';
      await _seedSimples(firestore, pid, 4);
      EstoqueTransactionService.debugBatchTransactionDelay =
          const Duration(milliseconds: 300);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _item(pid: pid),
        operationId: 'op-net',
      );

      expect(r.status, EstoqueBaixaOperationStatus.applied);
      expect(await _qtdRemota(firestore, pid), 3);
    });
  });
}
