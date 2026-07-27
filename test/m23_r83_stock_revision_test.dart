// M2.3-R8.3 — revisão monotônica, estado pendente explícito, relógio misto, offline, L7 combo.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/pending_server_timestamp.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_version_fields.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loja = 'loja-r83';
const _pid = 'prod-r83';
const _tamA = 'tam-a';
const _tamB = 'tam-b';

Map<String, dynamic> _remote({
  required int qA,
  required int qB,
  int revision = 0,
  String? operationId,
  DateTime? stockAt,
}) {
  return {
    'nome': 'Prod R83',
    'slug': _pid,
    'quantidade': qA + qB,
    'variacoes': {
      _tamA: {'sem-cor': qA},
      _tamB: {'sem-cor': qB},
    },
    'estoquePorTamanho': {_tamA: qA, _tamB: qB},
    kProdutoStockRevisionField: revision,
    if (operationId != null) kProdutoStockOperationIdField: operationId,
    if (stockAt != null)
      kProdutoStockUpdatedAtField: Timestamp.fromDate(stockAt),
  };
}

Produto _local({
  required int qA,
  required int qB,
  int stockRevision = 0,
  String? pendingOp,
  int? pendingBase,
  String? confirmedOp,
  DateTime? stockAt,
  DateTime? stockAtServer,
}) {
  return Produto(
    nome: 'Prod R83',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: qA + qB,
    precoUnitario: 50,
    categoria: 'Geral',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: _loja,
    idFirebase: _pid,
    slug: _pid,
    custoEditadoNoCadastro: true,
    variacoes: {
      _tamA: {'sem-cor': qA},
      _tamB: {'sem-cor': qB},
    },
    estoquePorTamanho: {_tamA: qA, _tamB: qB},
    stockRevision: stockRevision,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingBase,
    confirmedStockOperationId: confirmedOp,
    stockUpdatedAt: stockAt,
    stockUpdatedAtServer: stockAtServer,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveRootDir;

  setUpAll(() async {
    hiveRootDir = await Directory.systemTemp.createTemp('hive_r83_root_');
    Hive.init(hiveRootDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(ProdutoAdapter());
    }
  });

  tearDownAll(() async {
    try {
      await hiveRootDir.delete(recursive: true);
    } catch (_) {}
  });

  group('R8.3 — CLOCK relógio misto (sem DateTime para pendência)', () {
    test('CLOCK1 relógio local atrasado mantém pendência', () {
      const op = 'op-clock1';
      final local = _local(
        qA: 3,
        qB: 4,
        stockRevision: 5,
        pendingOp: op,
        pendingBase: 5,
        stockAt: DateTime(2026, 6, 15, 15, 5),
        stockAtServer: DateTime(2026, 6, 15, 15, 10),
      );
      final remote = _remote(qA: 5, qB: 7, revision: 5, stockAt: DateTime(2026, 6, 15, 15, 10));

      expect(hasPendingStockMutation(local), isTrue);
      expect(
        evaluatePullStockMergeByRevision(local: local, remoteData: remote),
        PullStockMergeDecision.preserveLocalGrade,
      );
      expect(
        local.stockUpdatedAt!.isBefore(local.stockUpdatedAtServer!),
        isTrue,
        reason: 'R8.2: relógio local atrasado — regra temporal daria falso',
      );
    });

    test('CLOCK2 confirmação por operationId encerra pendência', () {
      const op = 'op-clock2';
      final local = _local(
        qA: 3,
        qB: 4,
        stockRevision: 5,
        pendingOp: op,
        pendingBase: 5,
        stockAt: DateTime(2026, 6, 15, 15, 30),
        stockAtServer: DateTime(2026, 6, 15, 15, 10),
      );
      final remote = _remote(
        qA: 3,
        qB: 4,
        revision: 6,
        operationId: op,
        stockAt: DateTime(2026, 6, 15, 15, 11),
      );

      expect(
        evaluatePullStockMergeByRevision(local: local, remoteData: remote),
        PullStockMergeDecision.acceptRemote,
      );
      tryConfirmStockFromRemote(local, remote);
      expect(hasPendingStockMutation(local), isFalse);
      expect(local.stockRevision, 6);
      expect(local.confirmedStockOperationId, op);
    });

    test('CLOCK3 ajuste de relógio não altera pendência', () {
      const op = 'op-clock3';
      final local = _local(
        qA: 2,
        qB: 2,
        stockRevision: 1,
        pendingOp: op,
        pendingBase: 1,
      );
      local.stockUpdatedAt = DateTime(2026, 1, 1, 8, 0);
      expect(hasPendingStockMutation(local), isTrue);

      local.stockUpdatedAt = DateTime(2026, 12, 31, 23, 59);
      expect(hasPendingStockMutation(local), isTrue);

      local.stockUpdatedAt = DateTime(2020, 1, 1);
      expect(hasPendingStockMutation(local), isTrue);
    });
  });

  group('R8.3 — OFF offline', () {
    test('OFF1 venda offline cria pending e preserva contra remoto antigo', () {
      final p = _local(qA: 5, qB: 5, stockRevision: 3);
      markPendingStockMutation(p, operationId: 'off1', baseRevision: 3);
      p.variacoes![_tamA] = {'sem-cor': 4};

      final stale = _remote(qA: 5, qB: 5, revision: 3);
      expect(
        evaluatePullStockMergeByRevision(local: p, remoteData: stale),
        PullStockMergeDecision.preserveLocalGrade,
      );
    });

    test('OFF2 confirmação de A não encerra B', () {
      final p = _local(qA: 4, qB: 4, stockRevision: 2, pendingOp: 'op-B', pendingBase: 2);
      final remoteA = _remote(qA: 5, qB: 4, revision: 3, operationId: 'op-A');
      tryConfirmStockFromRemote(p, remoteA);
      expect(hasPendingStockMutation(p), isTrue);
      expect(p.pendingStockOperationId, 'op-B');
    });

    test('OFF4 restart Hive mantém pendência', () async {
      final boxName = 'off4_${DateTime.now().microsecondsSinceEpoch}';
      final box = await Hive.openBox<Produto>(boxName);
      final p = _local(qA: 3, qB: 3, stockRevision: 1);
      markPendingStockMutation(p, operationId: 'off4-restart', baseRevision: 1);
      await box.add(p);
      await box.close();

      final box2 = await Hive.openBox<Produto>(boxName);
      final read = box2.values.first;
      expect(read.pendingStockOperationId, 'off4-restart');
      expect(read.pendingStockBaseRevision, 1);
      await box2.close();
    });
  });

  group('R8.3 — SERVER_TIMESTAMP readback', () {
    test('SERVER_TIMESTAMP_READBACK_VALIDATED duas fases', () {
      final harness = TwoPhaseServerTimestampHarness(
        resolvedAt: DateTime.utc(2026, 6, 15, 15, 10),
      );
      harness.writePending('doc/1', {
        kProdutoStockUpdatedAtField: const PendingServerTimestamp(),
        kProdutoStockRevisionField: 7,
        kProdutoStockOperationIdField: 'readback-op',
      });

      expect(
        harness.valueBeforeReadback('doc/1', kProdutoStockUpdatedAtField),
        isA<PendingServerTimestamp>(),
      );

      final after = harness.valueAfterReadback('doc/1', kProdutoStockUpdatedAtField);
      expect(after, isA<Timestamp>());
      expect(
        (resolvePendingServerTimestamp(after) as DateTime).toUtc(),
        DateTime.utc(2026, 6, 15, 15, 10),
      );
    });
  });

  group('R8.3 — legado', () {
    test('LEGACY_COEXISTENCE_REQUIRES_FORCED_UPDATE matriz básica', () {
      expect(
        classifyRemoteStockWriter(_remote(qA: 1, qB: 1, revision: 2)),
        LegacyStockWriterKind.newApp,
      );
      expect(
        classifyRemoteStockWriter({'quantidade': 2, 'variacoes': {}}),
        LegacyStockWriterKind.legacyApp,
      );
    });
  });
}
