// M2.3-R8.2 — push/autosync, relógio misto, grade G7–G11, L2–L7, Hive, Firestore legado.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/produto_estoque_grade_snapshot.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_stock_version_fields.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stock_revision_client_build_test_support.dart';

const _loja = 'loja-r82-stock';
const _pid = 'prod-r82';
const _tamA = 'tam-a';
const _tamB = 'tam-b';

Map<String, dynamic> _remote({
  required int qA,
  required int qB,
  DateTime? stockAt,
  String? nome,
  int revision = 0,
  String? operationId,
}) {
  final variacoes = {
    _tamA: {'sem-cor': qA},
    _tamB: {'sem-cor': qB},
  };
  final estoque = {_tamA: qA, _tamB: qB};
  return {
    'nome': nome ?? 'Prod R82',
    'slug': _pid,
    'quantidade': qA + qB,
    'variacoes': variacoes,
    'estoquePorTamanho': estoque,
    kProdutoStockRevisionField: revision,
    if (operationId != null) kProdutoStockOperationIdField: operationId,
    if (stockAt != null)
      kProdutoStockUpdatedAtField: Timestamp.fromDate(stockAt),
    'updatedAt': Timestamp.fromDate(stockAt ?? DateTime(2026, 1, 1)),
  };
}

Produto _local({
  required int qA,
  required int qB,
  DateTime? stockAt,
  DateTime? stockAtServer,
  String nome = 'Prod R82',
  int stockRevision = 0,
  String? pendingOp,
  int? pendingBase,
}) {
  final variacoes = {
    _tamA: {'sem-cor': qA},
    _tamB: {'sem-cor': qB},
  };
  return Produto(
    nome: nome,
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
    variacoes: variacoes,
    estoquePorTamanho: {_tamA: qA, _tamB: qB},
    stockUpdatedAt: stockAt,
    stockUpdatedAtServer: stockAtServer,
    stockRevision: stockRevision,
    pendingStockOperationId: pendingOp,
    pendingStockBaseRevision: pendingBase,
  );
}

int _cell(Produto p, String tam) {
  final m = p.variacoes?[tam];
  if (m is! Map) return -1;
  final v = m['sem-cor'];
  if (v is num) return v.toInt();
  return -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    initializeCompatibleStockClientBuildForTest(285);
  });

  tearDown(resetStockClientBuildForTest);

  group('R8.2 — contrato relógio misto', () {
    test('MIXED_CLOCK_VERSIONING_NOT_SAFE sem âncora server', () {
      final local = _local(
        qA: 3,
        qB: 4,
        stockAt: DateTime.now().add(const Duration(hours: 5)),
        stockAtServer: null,
        pendingOp: 'op-mixed',
        pendingBase: 0,
      );
      final remote = _remote(
        qA: 5,
        qB: 7,
        stockAt: DateTime(2026, 1, 1),
        revision: 0,
      );
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: DateTime(2026, 1, 1),
          localStockUpdatedAt: local.stockUpdatedAt,
        ),
        PullStockMergeDecision.preserveLocalGrade,
        reason: 'pendência explícita — relógio não decide',
      );
    });

    test('STOCK_REVISION_VERSIONING com revisão remota posterior', () {
      final serverAt = DateTime(2026, 6, 15, 12, 0);
      final local = _local(
        qA: 3,
        qB: 4,
        stockAt: DateTime.now(),
        stockAtServer: DateTime(2026, 6, 15, 11, 0),
        stockRevision: 2,
      );
      final remote = _remote(qA: 8, qB: 4, stockAt: serverAt, revision: 5);
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: serverAt,
          localStockUpdatedAt: local.stockUpdatedAt,
          localStockUpdatedAtServer: local.stockUpdatedAtServer,
        ),
        PullStockMergeDecision.acceptRemote,
      );
    });
  });

  group('R8.2 — G7–G11 grade', () {
    test('G7 ordem de mapas irrelevante', () {
      final a = ProdutoEstoqueGradeSnapshot.fromRemote({
        'variacoes': {
          _tamB: {'sem-cor': 4},
          _tamA: {'sem-cor': 3},
        },
        'quantidade': 7,
      });
      final b = ProdutoEstoqueGradeSnapshot.fromRemote({
        'variacoes': {
          _tamA: {'sem-cor': 3},
          _tamB: {'sem-cor': 4},
        },
        'quantidade': 7,
      });
      expect(a.gradeEquals(b), isTrue);
    });

    test('G8 mesma label variacaoId diferente', () {
      final a = ProdutoEstoqueGradeSnapshot.fromRemote({
        'variacoes': {_tamA: {'sem-cor': 3}},
        'quantidade': 3,
      });
      final b = ProdutoEstoqueGradeSnapshot.fromRemote({
        'variacoes': {_tamB: {'sem-cor': 3}},
        'quantidade': 3,
      });
      expect(a.gradeEquals(b), isFalse);
    });

    test('G9 int versus double normalizado', () {
      final snap = ProdutoEstoqueGradeSnapshot.fromRemote({
        'variacoes': {_tamA: {'sem-cor': 3.0}},
        'quantidade': 3,
      });
      expect(snap.cells[ProdutoEstoqueGradeSnapshot.variacaoId(_tamA)], 3);
    });

    test('G10 legado sem variacoes usa estoquePorTamanho', () {
      final snap = ProdutoEstoqueGradeSnapshot.fromRemote({
        'estoquePorTamanho': {_tamA: 2, _tamB: 5},
        'quantidade': 7,
      });
      expect(snap.cells[ProdutoEstoqueGradeSnapshot.variacaoId(_tamA)], 2);
      expect(snap.quantidadeTotal, 7);
    });

    test('G11 duplicata determinística (última chave vence)', () {
      final vars = <String, dynamic>{
        _tamA: <String, dynamic>{'sem-cor': 7},
      };
      final cells = ProdutoEstoqueGradeSnapshot.fromRemote({
        'variacoes': vars,
        'quantidade': 7,
      }).cells;
      expect(cells[ProdutoEstoqueGradeSnapshot.variacaoId(_tamA)], 7);
    });
  });

  group('R8.2 — push/autosync P1–P6', () {
    test('P1 objeto stale pré-venda não empurra remoto', () {
      final stale = _local(
        qA: 5,
        qB: 7,
        stockAt: DateTime(2020, 1, 1),
        stockAtServer: DateTime(2020, 1, 1),
      );
      final remote = _remote(
        qA: 3,
        qB: 4,
        stockAt: DateTime(2026, 6, 15),
        revision: 3,
      );
      expect(
        evaluatePushStockSkip(local: stale, existingData: remote),
        isTrue,
      );
    });

    test('P2 entrada legítima posterior permite push', () {
      final local = _local(
        qA: 8,
        qB: 4,
        stockAt: DateTime(2026, 6, 20),
        stockAtServer: DateTime(2026, 6, 10),
        stockRevision: 5,
      );
      final remote = _remote(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 15), revision: 2);
      expect(
        evaluatePushStockSkip(local: local, existingData: remote),
        isFalse,
      );
    });

    test('P3 remoto pós-venda bloqueia push stale', () {
      final stale = _local(qA: 5, qB: 7, stockAtServer: DateTime(2020, 1, 1));
      final remote = _remote(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 15), revision: 3);
      expect(evaluatePushStockSkip(local: stale, existingData: remote), isTrue);
    });

    test('P4 relógio B adiantado não vence por horário', () {
      final stale = _local(
        qA: 5,
        qB: 7,
        stockAt: DateTime(2020, 1, 1),
        stockAtServer: DateTime(2020, 1, 1),
      );
      stale.updatedAt = DateTime.now().add(const Duration(minutes: 5));
      final remote = _remote(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 15), revision: 3);
      expect(
        ProdutosFirestoreService.shouldSkipStaleProdutoPushOnAutoSync(
          local: stale,
          existingData: remote,
          bumpHiveTimestamp: false,
        ),
        isTrue,
      );
    });

    test('P5 relógio B atrasado não descarta operação nova', () {
      final local = _local(
        qA: 8,
        qB: 4,
        stockAt: DateTime(2026, 6, 25),
        stockAtServer: DateTime(2020, 1, 1),
        stockRevision: 4,
      );
      final remote = _remote(qA: 3, qB: 4, stockAt: DateTime(2020, 1, 2), revision: 1);
      expect(evaluatePushStockSkip(local: local, existingData: remote), isFalse);
    });

    test('P6 nome novo em objeto stale não autoriza grade antiga no push', () {
      final stale = _local(
        qA: 5,
        qB: 7,
        stockAtServer: DateTime(2020, 1, 1),
        nome: 'Nome novo',
      );
      stale.updatedAt = DateTime.now();
      final remote = _remote(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 15), revision: 3);
      expect(
        evaluatePushStockSkip(local: stale, existingData: remote),
        isTrue,
        reason: 'PUSH_TIME_HEURISTIC_NOT_SAFE — usa grade+stockUpdatedAt',
      );
    });
  });

  group('R8.2 — Firestore legado F1–F5', () {
    test('F1 legado sem stockUpdatedAt preserva local em regressão', () {
      final local = _local(qA: 3, qB: 4, stockAtServer: DateTime(2026, 6, 10));
      final remote = {
        'quantidade': 12,
        'variacoes': {
          _tamA: {'sem-cor': 5},
          _tamB: {'sem-cor': 7},
        },
      };
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: null,
          localStockUpdatedAt: local.stockUpdatedAt,
          localStockUpdatedAtServer: local.stockUpdatedAtServer,
        ),
        PullStockMergeDecision.preserveLocalGrade,
      );
    });

    test('F3 app novo com stockUpdatedAt aceita remoto posterior', () {
      final local = _local(qA: 3, qB: 4, stockAtServer: DateTime(2026, 1, 1));
      final remoteAt = DateTime(2026, 6, 20);
      final remote = _remote(qA: 6, qB: 6, stockAt: remoteAt, revision: 2);
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: remoteAt,
          localStockUpdatedAt: local.stockUpdatedAt,
          localStockUpdatedAtServer: local.stockUpdatedAtServer,
        ),
        PullStockMergeDecision.acceptRemote,
      );
    });

    test('F4 stockUpdatedAt inválido tratado como null', () {
      expect(
        parseFirestoreStockUpdatedAtField({'stockUpdatedAt': 'invalid'}),
        isNull,
      );
    });
  });

  group('R8.2 — Hive HIVE1/HIVE2', () {
    late String hivePath;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_r82_');
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

    test('HIVE1 registro sem stockUpdatedAtServer lê null', () async {
      final box = await Hive.openBox<Produto>('hive1_${DateTime.now().microsecondsSinceEpoch}');
      final p = _local(qA: 2, qB: 3, stockAt: DateTime(2026, 1, 1));
      await box.add(p);
      final read = box.values.first;
      expect(read.stockUpdatedAt, isNotNull);
      expect(read.stockUpdatedAtServer, isNull);
      await box.close();
    });

    test('HIVE2 stockUpdatedAtServer persiste após reabrir', () async {
      final name = 'hive2_${DateTime.now().microsecondsSinceEpoch}';
      final at = DateTime(2026, 6, 15, 10, 30);
      {
        final box = await Hive.openBox<Produto>(name);
        final p = _local(qA: 2, qB: 3);
        applyServerStockVersionToProduto(p, at);
        await box.add(p);
        await box.close();
      }
      final box2 = await Hive.openBox<Produto>(name);
      final read = box2.values.first;
      expect(read.stockUpdatedAtServer?.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
      expect(read.stockUpdatedAt?.millisecondsSinceEpoch, at.millisecondsSinceEpoch);
      await box2.close();
    });
  });

  group('R8.2 — L2/L4/L5 integração', () {
    late FakeFirebaseFirestore firestore;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;
    late String hivePath;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_r82_int_');
      hivePath = dir.path;
      Hive.init(hivePath);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
    });

    tearDownAll(() async {
      try {
        await Directory(hivePath).delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => _loja;
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      EstoqueService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_r82_$s');
      clientesBox = await Hive.openBox<Cliente>('c_r82_$s');
      vendasBox = await Hive.openBox<Venda>('v_r82_$s');
      await firestore
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .set(_remote(qA: 5, qB: 7, stockAt: DateTime(2026, 1, 1)));
      await produtosBox.add(_local(qA: 5, qB: 7, stockAtServer: DateTime(2026, 1, 1)));
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      EstoqueService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Venda> vender() async {
      final c = Cliente(
        nome: 'C R82',
        telefone: '11999990082',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _loja,
      );
      await clientesBox.add(c);
      return VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: [
          VendaItem(
            produtoNome: 'Prod R82',
            quantidade: 2,
            precoUnitario: 50,
            productId: _pid,
            tamanho: _tamA,
          ),
          VendaItem(
            produtoNome: 'Prod R82',
            quantidade: 3,
            precoUnitario: 50,
            productId: _pid,
            tamanho: _tamB,
          ),
        ],
        dinheiro: 250,
        lojaId: _loja,
      );
    }

    test('L2 exclusão legítima restaura estoque e aceita pull', () async {
      final venda = await vender();
      expect(_cell(produtosBox.values.first, _tamA), 3);
      final stockMsBefore =
          produtosBox.values.first.stockUpdatedAt?.millisecondsSinceEpoch;

      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: venda,
        produtosBox: produtosBox,
        lojaId: _loja,
      );

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _loja,
        produtosBox: produtosBox,
        preferRemoteQuantity: true,
      );
      final after = produtosBox.values.first;
      expect(_cell(after, _tamA), 5);
      expect(_cell(after, _tamB), 7);
      expect(after.stockUpdatedAtServer, isNotNull);
      if (stockMsBefore != null) {
        expect(
          after.stockUpdatedAtServer!.millisecondsSinceEpoch,
          greaterThanOrEqualTo(stockMsBefore),
        );
      }
    });

    test('L4 devolução via EstoqueService.atualizarEstoque', () async {
      await vender();
      final result = await EstoqueService.atualizarEstoque(
        produtosBox: produtosBox,
        lojaId: _loja,
        produtoId: _pid,
        tamanho: _tamA,
        cor: '',
        quantidade: 1,
        operacao: 'devolucao',
      );
      expect(result.sucesso, isTrue);
      expect(_cell(produtosBox.values.first, _tamA), 4);
      expect(produtosBox.values.first.stockUpdatedAt, isNotNull);
    });

    test('L5 correção administrativa via entrada manual', () async {
      await vender();
      final result = await EstoqueService.atualizarEstoque(
        produtosBox: produtosBox,
        lojaId: _loja,
        produtoId: _pid,
        tamanho: _tamA,
        cor: '',
        quantidade: 5,
        operacao: 'entrada_compra',
      );
      expect(result.sucesso, isTrue);
      expect(_cell(produtosBox.values.first, _tamA), 8);
    });
  });
}
