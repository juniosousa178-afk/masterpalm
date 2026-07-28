// M2.3-R8.1 — versionamento de estoque, grade por variação, entradas legítimas.

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
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stock_revision_client_build_test_support.dart';

const _loja = 'loja-r81-stock-version';
const _pid = 'prod-r81-grade';
const _tamA = 'var-a';
const _tamB = 'var-b';
const _tamC = 'var-c';

Map<String, dynamic> _gradeRemote({
  required int qA,
  required int qB,
  DateTime? stockAt,
  DateTime? updatedAt,
  Map<String, int>? extraTam,
  int revision = 0,
  String? operationId,
}) {
  final variacoes = <String, dynamic>{
    _tamA: {'sem-cor': qA},
    _tamB: {'sem-cor': qB},
    if (extraTam != null)
      for (final e in extraTam.entries) e.key: {'sem-cor': e.value},
  };
  final estoque = <String, int>{
    _tamA: qA,
    _tamB: qB,
    if (extraTam != null) ...extraTam,
  };
  final total = estoque.values.fold(0, (a, b) => a + b);
  return {
    'nome': 'Prod R81',
    'slug': _pid,
    'quantidade': total,
    'variacoes': variacoes,
    'estoquePorTamanho': estoque,
    if (revision > 0) kProdutoStockRevisionField: revision,
    if (operationId != null) kProdutoStockOperationIdField: operationId,
    if (stockAt != null)
      kProdutoStockUpdatedAtField: Timestamp.fromDate(stockAt),
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt),
  };
}

Produto _produtoLocal({
  required int qA,
  required int qB,
  DateTime? stockAt,
  DateTime? updatedAt,
  Map<String, int>? extraTam,
}) {
  final variacoes = <String, dynamic>{
    _tamA: {'sem-cor': qA},
    _tamB: {'sem-cor': qB},
    if (extraTam != null)
      for (final e in extraTam.entries) e.key: {'sem-cor': e.value},
  };
  final estoque = <String, int>{
    _tamA: qA,
    _tamB: qB,
    if (extraTam != null) ...extraTam,
  };
  return Produto(
    nome: 'Prod R81',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: estoque.values.fold(0, (a, b) => a + b),
    precoUnitario: 50,
    categoria: 'Geral',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: _loja,
    idFirebase: _pid,
    slug: _pid,
    custoEditadoNoCadastro: true,
    variacoes: variacoes,
    estoquePorTamanho: estoque,
    stockUpdatedAt: stockAt,
    updatedAt: updatedAt ?? stockAt,
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

  group('R8.1 — regra temporal (2s) substituída', () {
    test('HEURISTIC_TIME_WINDOW_NOT_JUSTIFIED — decisão usa grade + stockUpdatedAt',
        () {
      final local = _produtoLocal(
        qA: 3,
        qB: 4,
        stockAt: DateTime(2026, 6, 10, 12, 0, 0),
      );
      final remote = _gradeRemote(
        qA: 5,
        qB: 7,
        stockAt: DateTime(2026, 6, 10, 11, 59, 59), // anterior ao local
      );
      expect(
        ProdutosFirestoreService.shouldPreserveLocalStockOnRemoteRegression(
          local: local,
          remoteData: remote,
        ),
        isTrue,
        reason: 'grade regressa; stockUpdatedAt remoto não é posterior',
      );
    });
  });

  group('R8.1 — G1–G6 grade', () {
    test('G1 remoto antigo total maior preserva local', () {
      final local = _produtoLocal(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 10));
      final remote = _gradeRemote(
        qA: 5,
        qB: 7,
        updatedAt: DateTime(2020, 1, 1),
      );
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: null,
          localStockUpdatedAt: local.stockUpdatedAt,
        ),
        PullStockMergeDecision.preserveLocalGrade,
      );
    });

    test('G2 mesmo total distribuição antiga não regride A', () {
      final local = _produtoLocal(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 10));
      final remote = _gradeRemote(qA: 5, qB: 2, updatedAt: DateTime(2020, 1, 1));
      expect(
        ProdutosFirestoreService.shouldPreserveLocalStockOnRemoteRegression(
          local: local,
          remoteData: remote,
        ),
        isTrue,
      );
    });

    test('G3 total menor mas célula A maior → preservar', () {
      final local = _produtoLocal(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 10));
      final remote = _gradeRemote(qA: 5, qB: 1, updatedAt: DateTime(2020, 1, 1));
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: null,
          localStockUpdatedAt: local.stockUpdatedAt,
        ),
        PullStockMergeDecision.preserveLocalGrade,
      );
    });

    test('G4 variação removida no remoto antigo → preservar', () {
      final local = _produtoLocal(
        qA: 3,
        qB: 4,
        stockAt: DateTime(2026, 6, 10),
        extraTam: {_tamC: 2},
      );
      final remote = _gradeRemote(qA: 5, qB: 7, updatedAt: DateTime(2020, 1, 1));
      expect(
        ProdutosFirestoreService.shouldPreserveLocalStockOnRemoteRegression(
          local: local,
          remoteData: remote,
        ),
        isTrue,
      );
    });

    test('G5 nova variação legítima com stockUpdatedAt posterior → aceitar', () {
      final local = _produtoLocal(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 10));
      final remote = _gradeRemote(
        qA: 3,
        qB: 4,
        extraTam: {_tamC: 2},
        stockAt: DateTime(2026, 6, 10, 12, 5),
        revision: 2,
      );
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: DateTime(2026, 6, 10, 12, 5),
          localStockUpdatedAt: local.stockUpdatedAt,
        ),
        PullStockMergeDecision.acceptRemote,
      );
    });

    test('G6 mesma variacaoId qty legítima com stockUpdatedAt posterior', () {
      final local = _produtoLocal(qA: 3, qB: 4, stockAt: DateTime(2026, 6, 10));
      final remote = _gradeRemote(
        qA: 8,
        qB: 4,
        stockAt: DateTime(2026, 6, 10, 13, 0),
        revision: 2,
      );
      expect(
        evaluatePullStockMerge(
          local: local,
          remoteData: remote,
          remoteStockUpdatedAt: DateTime(2026, 6, 10, 13, 0),
          localStockUpdatedAt: local.stockUpdatedAt,
        ),
        PullStockMergeDecision.acceptRemote,
      );
    });
  });

  group('R8.1 — L1–L5 entradas legítimas (integração)', () {
    late FakeFirebaseFirestore firestore;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;
    late String hivePath;

    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('hive_r81_');
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
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_r81_$s');
      clientesBox = await Hive.openBox<Cliente>('c_r81_$s');
      vendasBox = await Hive.openBox<Venda>('v_r81_$s');
      await firestore
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .set(_gradeRemote(qA: 5, qB: 7, stockAt: DateTime(2026, 1, 1)));
      await produtosBox.add(_produtoLocal(qA: 5, qB: 7, stockAt: DateTime(2026, 1, 1)));
    });

    tearDown(() async {
      VendasService.debugVendasBoxAddOverride = null;
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Venda> vender2e3() async {
      final c = Cliente(
        nome: 'C',
        telefone: '11999990002',
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
            produtoNome: 'Prod R81',
            quantidade: 2,
            precoUnitario: 50,
            productId: _pid,
            tamanho: _tamA,
          ),
          VendaItem(
            produtoNome: 'Prod R81',
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

    test('L1 cancelamento legítimo restaura estoque no Hive após pull', () async {
      final venda = await vender2e3();
      final p = produtosBox.values.first;
      expect(_cell(p, _tamA), 3);
      expect(_cell(p, _tamB), 4);

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
    });

    test('L3 entrada manual remota aceita com stockUpdatedAt posterior', () async {
      await vender2e3();
      final stockMsBefore =
          produtosBox.values.first.stockUpdatedAt?.millisecondsSinceEpoch;
      expect(stockMsBefore, isNotNull);
      final remoteAt = DateTime.now().add(const Duration(hours: 1));
      await firestore
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .set(_gradeRemote(qA: 8, qB: 4, stockAt: remoteAt, updatedAt: remoteAt),
              SetOptions(merge: true));

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _loja,
        produtosBox: produtosBox,
        preferRemoteQuantity: true,
      );
      final after = produtosBox.values.first;
      expect(_cell(after, _tamA), 8);
      expect(_cell(after, _tamB), 4);
      expect(after.stockUpdatedAt, isNotNull);
      expect(
        after.stockUpdatedAt!.millisecondsSinceEpoch,
        greaterThan(stockMsBefore!),
      );
      expect(
        after.stockUpdatedAt!.millisecondsSinceEpoch,
        greaterThanOrEqualTo(remoteAt.millisecondsSinceEpoch - 1000),
      );
    });
  });

  group('R8.1 — escritor real stale (sem inject)', () {
    late FakeFirebaseFirestore firestore;
    late Box<Produto> produtosBox;
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => _loja;
      firestore = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = firestore;
      ProdutosFirestoreService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      produtosBox = await Hive.openBox<Produto>('p_real_$s');
      clientesBox = await Hive.openBox<Cliente>('c_real_$s');
      vendasBox = await Hive.openBox<Venda>('v_real_$s');
      await firestore
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .set(_gradeRemote(qA: 5, qB: 7, stockAt: DateTime(2026, 1, 1)));
      await produtosBox.add(_produtoLocal(qA: 5, qB: 7, stockAt: DateTime(2026, 1, 1)));
    });

    tearDown(() async {
      EstoqueTransactionService.debugFirestoreOverride = null;
      ProdutosFirestoreService.debugFirestoreOverride = null;
      await produtosBox.close();
      await clientesBox.close();
      await vendasBox.close();
    });

    test('REAL-1 instância B com objeto stale não sobrescreve remoto pós-venda',
        () async {
      final staleB = _produtoLocal(
        qA: 5,
        qB: 7,
        stockAt: DateTime(2020, 1, 1),
        updatedAt: DateTime(2020, 1, 1),
      );

      final c = Cliente(
        nome: 'C',
        telefone: '11999990003',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _loja,
      );
      await clientesBox.add(c);
      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: [
          VendaItem(
            produtoNome: 'Prod R81',
            quantidade: 2,
            precoUnitario: 50,
            productId: _pid,
            tamanho: _tamA,
          ),
        ],
        dinheiro: 100,
        lojaId: _loja,
      );

      expect(_cell(produtosBox.values.first, _tamA), 3);

      final remotePosVenda = _gradeRemote(
        qA: 3,
        qB: 7,
        stockAt: DateTime(2026, 6, 15, 12, 0),
        revision: 1,
        operationId: 'sale-op-real1',
      );
      await firestore
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .set(remotePosVenda, SetOptions(merge: true));

      expect(
        evaluatePushStockSkip(local: staleB, existingData: remotePosVenda),
        isTrue,
        reason: 'AUTO_SYNC_STALE_WRITE_BLOCKED_BY_EXISTING_GUARD',
      );

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        staleB,
        lojaId: _loja,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
        writeOrigin: 'test.real1_instance_b',
      );
      expect(
        status,
        anyOf(
          ProdutoSyncRemotoStatus.semMudancas,
          ProdutoSyncRemotoStatus.falhaRemota,
        ),
        reason: 'push stale bloqueado',
      );

      final remotoAposB = await firestore
          .collection('lojas')
          .doc(_loja)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .get();
      expect(_cellFromMap(remotoAposB.data()?['variacoes'] as Map?, _tamA), 3);
    });
  });
}

int _cellFromMap(Map? vars, String tam) {
  final m = vars?[tam];
  if (m is! Map) return -1;
  final v = m['sem-cor'];
  if (v is num) return v.toInt();
  return -1;
}
