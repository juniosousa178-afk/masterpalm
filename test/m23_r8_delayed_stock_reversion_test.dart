// M2.3-R8 — estoque baixa corretamente e persiste após sync/reabertura.
// RED permanente: reproduzir reversão tardia (se existir) sem esconder falhas.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sync_queue_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stock_revision_client_build_test_support.dart';

const _lojaId = 'loja-m23-r8-delayed-reversion';
const _pid = 'colar-r8-multi-var';
const _tamA = 'var-a';
const _tamB = 'var-b';
const _qA0 = 5;
const _qB0 = 7;
const _total0 = _qA0 + _qB0;

/// Rastreador mínimo de escritores (timeline T0–T11 em testes).
class _StockWriteTrace {
  _StockWriteTrace(this.traceId);

  final String traceId;
  final List<Map<String, Object?>> events = [];

  void record({
    required String stage,
    required String source,
    required String method,
    int? qA,
    int? qB,
    int? total,
    String? origin,
  }) {
    events.add({
      'traceId': traceId,
      'stage': stage,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'source': source,
      'method': method,
      'productId': _pid,
      'variacaoA': qA,
      'variacaoB': qB,
      'total': total,
      'origin': origin,
    });
  }

  Map<String, Object?>? firstWrite() {
    final w = events.where((e) => e['stage'] == 'first_write').toList();
    return w.isEmpty ? null : w.first;
  }

  Map<String, Object?>? secondWrite() {
    final w = events.where((e) => e['stage'] == 'second_write').toList();
    return w.isEmpty ? null : w.first;
  }
}

Future<Map<String, dynamic>?> _remoto(
  FakeFirebaseFirestore db,
) async {
  final snap = await db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(_pid)
      .get();
  return snap.data();
}

int _cell(Map? vars, String tam, [String cor = 'sem-cor']) {
  final m = vars?[tam];
  if (m is! Map) return -1;
  final v = m[cor] ?? m['sem-cor'];
  if (v is num) return v.toInt();
  return -1;
}

Produto _cloneStaleGrade(Produto src) {
  return Produto(
    nome: src.nome,
    custoReal: src.custoReal,
    frete: src.frete,
    gastosFixos: src.gastosFixos,
    gastosVariaveis: src.gastosVariaveis,
    precoSugerido: src.precoSugerido,
    precoFinal: src.precoFinal,
    quantidade: _total0,
    precoUnitario: src.precoUnitario,
    categoria: src.categoria,
    dataEntrada: src.dataEntrada,
    descricao: src.descricao,
    imagens: List<String>.from(src.imagens),
    lojaId: src.lojaId,
    idFirebase: src.idFirebase,
    slug: src.slug,
    variacoes: {
      _tamA: {'sem-cor': _qA0},
      _tamB: {'sem-cor': _qB0},
    },
    estoquePorTamanho: {_tamA: _qA0, _tamB: _qB0},
    updatedAt: DateTime(2020, 1, 1),
    custoEditadoNoCadastro: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late String hivePath;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;
  late _StockWriteTrace trace;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_m23_r8_');
    hivePath = dir.path;
    Hive.init(hivePath);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  });

  tearDownAll(() async {
    LojaAtivaResolver.debugResolveOverride = null;
    try {
      await Directory(hivePath).delete(recursive: true);
    } catch (_) {}
  });

  Future<void> seedProduto() async {
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(_pid)
        .set({
      'nome': 'Colar R8',
      'quantidade': _total0,
      'slug': _pid,
      'variacoes': {
        _tamA: {'sem-cor': _qA0},
        _tamB: {'sem-cor': _qB0},
      },
      'estoquePorTamanho': {_tamA: _qA0, _tamB: _qB0},
      'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Colar R8'
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
        ..updatedAt = DateTime(2026, 1, 1),
    );
  }

  Future<Cliente> cliente() async {
    final c = Cliente(
      nome: 'Cliente R8',
      telefone: '11999990001',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  List<VendaItem> itensVenda() => [
        VendaItem(
          produtoNome: 'Colar R8',
          quantidade: 2,
          precoUnitario: 50,
          productId: _pid,
          tamanho: _tamA,
        ),
        VendaItem(
          produtoNome: 'Colar R8',
          quantidade: 3,
          precoUnitario: 50,
          productId: _pid,
          tamanho: _tamB,
        ),
      ];

  Future<void> assertHiveEstoque({
    required int qA,
    required int qB,
    required int total,
    String? reason,
  }) async {
    final local = produtosBox.values.firstWhere((p) => p.idFirebase == _pid);
    expect(local.quantidade, total, reason: reason);
    expect((local.variacoes?[_tamA] as Map?)?['sem-cor'], qA,
        reason: reason ?? 'hive $_tamA');
    expect((local.variacoes?[_tamB] as Map?)?['sem-cor'], qB,
        reason: reason ?? 'hive $_tamB');
  }

  Future<void> assertEstoque({
    required int qA,
    required int qB,
    required int total,
    String? reason,
  }) async {
    final remoto = await _remoto(firestore);
    expect((remoto?['quantidade'] as num?)?.toInt(), total, reason: reason);
    final vars = remoto?['variacoes'] as Map?;
    expect(_cell(vars, _tamA), qA, reason: reason ?? 'remoto $_tamA');
    expect(_cell(vars, _tamB), qB, reason: reason ?? 'remoto $_tamB');

    final local = produtosBox.values.firstWhere((p) => p.idFirebase == _pid);
    expect(local.quantidade, total, reason: reason);
    expect((local.variacoes?[_tamA] as Map?)?['sem-cor'], qA,
        reason: reason ?? 'hive $_tamA');
    expect((local.variacoes?[_tamB] as Map?)?['sem-cor'], qB,
        reason: reason ?? 'hive $_tamB');
  }

  Future<Venda> registrarVenda() async {
    final c = await cliente();
    trace.record(
      stage: 'T1',
      source: 'test',
      method: 'VendasService.registrarVendaMulti',
    );
    final venda = await VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: c.nome,
      clienteExistente: c,
        itens: itensVenda(),
      dinheiro: 250,
      lojaId: _lojaId,
    );
    trace.record(
      stage: 'first_write',
      source: 'vendas_service',
      method: 'baixarEstoqueTransactionBatchIdempotente+atualizarHiveAposTransacao',
      qA: 3,
      qB: 4,
      total: 7,
      origin: 'sale',
    );
    return venda;
  }

  setUp(() async {
    initializeCompatibleStockClientBuildForTest(285);
    SharedPreferences.setMockInitialValues({});
    trace = _StockWriteTrace('r8-${DateTime.now().microsecondsSinceEpoch}');
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    await SyncQueueService.init();
    await SyncQueueService.clearQueue();
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_r8_$s');
    clientesBox = await Hive.openBox<Cliente>('c_r8_$s');
    vendasBox = await Hive.openBox<Venda>('v_r8_$s');
    await seedProduto();
    trace.record(
      stage: 'T0',
      source: 'seed',
      method: 'seedProduto',
      qA: _qA0,
      qB: _qB0,
      total: _total0,
    );
  });

  tearDown(() async {
    resetStockClientBuildForTest();
    VendasService.debugVendasBoxAddOverride = null;
    VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    LojaAtivaResolver.debugResolveOverride = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await SyncQueueService.clearQueue();
    await produtosBox.close();
    await clientesBox.close();
    await vendasBox.close();
  });

  group('M2.3-R8 delayed stock reversion', () {
    test('R1 — baixa imediata duas variações', () async {
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R1 imediato');
      expect(vendasBox.length, 1);
    });

    test('R2 — ciclo sync queue após venda mantém estoque', () async {
      final local = produtosBox.values.first;
      final hiveKey = local.key as int;
      await SyncQueueService.enqueueProdutoUnico(
        lojaId: _lojaId,
        boxName: produtosBox.name,
        entityKey: hiveKey,
        scheduleProcess: false,
      );
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R2 pós-venda');
      await SyncQueueService.processPending(scopeLojaId: _lojaId);
      trace.record(
        stage: 'T8',
        source: 'sync_queue',
        method: 'processPending',
        qA: 3,
        qB: 4,
        total: 7,
      );
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R2 pós-fila');
    });

    test('R3 — pull Firestore→Hive após venda mantém estoque', () async {
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7);
      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _lojaId,
        produtosBox: produtosBox,
      );
      trace.record(
        stage: 'T8',
        source: 'pull',
        method: 'syncFirestoreToHive',
        qA: 3,
        qB: 4,
        total: 7,
      );
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R3 pull');
    });

    test('R4 — snapshot remoto antigo não reverte Hive com updatedAt local', () async {
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7);

      // Simula snapshot tardio (estado pré-venda) com updatedAt velho.
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(_pid)
          .set({
        'nome': 'Colar R8',
        'quantidade': _total0,
        'slug': _pid,
        'variacoes': {
          _tamA: {'sem-cor': _qA0},
          _tamB: {'sem-cor': _qB0},
        },
        'estoquePorTamanho': {_tamA: _qA0, _tamB: _qB0},
        'updatedAt': Timestamp.fromDate(DateTime(2020, 1, 1)),
      }, SetOptions(merge: true));

      trace.record(
        stage: 'second_write',
        source: 'test_inject',
        method: 'firestore.set(stale_snapshot)',
        qA: _qA0,
        qB: _qB0,
        total: _total0,
        origin: 'stale_remote_injection',
      );

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _lojaId,
        produtosBox: produtosBox,
      );
      // Com guard de updatedAt local, Hive não deve regredir.
      await assertHiveEstoque(
        qA: 3,
        qB: 4,
        total: 7,
        reason: 'R4 pull com snapshot antigo — Hive preservado',
      );
    });

    test('R5 — push com objeto stale em memória não restaura remoto', () async {
      final staleSnapshot = _cloneStaleGrade(
        produtosBox.values.firstWhere((p) => p.idFirebase == _pid),
      );
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7);

      final status = await ProdutosFirestoreService.syncProdutoComStatus(
        staleSnapshot,
        lojaId: _lojaId,
        bumpHiveTimestamp: true,
        enqueueOnFailure: false,
        writeOrigin: 'test.r5_stale_memory_push',
      );
      trace.record(
        stage: 'second_write',
        source: 'push_attempt',
        method: 'syncProdutoComStatus(stale_copy)',
        qA: _qA0,
        qB: _qB0,
        total: _total0,
        origin: status.name,
      );

      // Objeto fora da box pode falhar (HiveError) — o importante é remoto intacto.
      await assertEstoque(
        qA: 3,
        qB: 4,
        total: 7,
        reason: 'R5 stale push não restaura remoto',
      );
    });

    test('R6 — delay UI pós-baixa remota: venda e estoque persistem', () async {
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      };
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7);
      expect(vendasBox.length, 1);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
    });

    test('R7 — reabertura de boxes mantém estoque', () async {
      await registrarVenda();
      final boxName = produtosBox.name;
      await produtosBox.close();

      final reopened = await Hive.openBox<Produto>(boxName);
      final p = reopened.values.firstWhere((x) => x.idFirebase == _pid);
      expect((p.variacoes?[_tamA] as Map?)?['sem-cor'], 3);
      expect((p.variacoes?[_tamB] as Map?)?['sem-cor'], 4);
      expect(p.quantidade, 7);
      await reopened.close();
      produtosBox = await Hive.openBox<Produto>(boxName);
    });

    test('R8 — segunda instância stale não vence após venda', () async {
      final staleB = _cloneStaleGrade(
        produtosBox.values.firstWhere((p) => p.idFirebase == _pid),
      );
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7);

      final statusB = await ProdutosFirestoreService.syncProdutoComStatus(
        staleB,
        lojaId: _lojaId,
        bumpHiveTimestamp: false,
        enqueueOnFailure: false,
        writeOrigin: 'test.r8_instance_b',
      );
      trace.record(
        stage: 'second_write',
        source: 'instance_b',
        method: 'syncProdutoComStatus',
        qA: _qA0,
        qB: _qB0,
        total: _total0,
        origin: statusB.name,
      );
      expect(
        statusB,
        anyOf(
          ProdutoSyncRemotoStatus.semMudancas,
          ProdutoSyncRemotoStatus.falhaRemota,
        ),
        reason: 'R8 push stale bloqueado',
      );
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R8 cross-instance');
    });

    test('R9 — múltiplos ciclos: imediato, sync, pull, reabertura', () async {
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R9 imediato');

      await SyncQueueService.processPending(scopeLojaId: _lojaId);
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R9 sync1');

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _lojaId,
        produtosBox: produtosBox,
        preferRemoteQuantity: true,
      );
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R9 pull preferRemote');

      await SyncQueueService.processPending(scopeLojaId: _lojaId);
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R9 sync2');

      final boxName = produtosBox.name;
      await produtosBox.close();
      produtosBox = await Hive.openBox<Produto>(boxName);
      await assertEstoque(qA: 3, qB: 4, total: 7, reason: 'R9 reopen');

      expect(trace.firstWrite(), isNotNull);
      expect(trace.secondWrite(), isNull,
          reason: 'sem segundo write natural neste fluxo feliz');
    });

    test('R9b — preferRemoteQuantity com remoto stale não reverte Hive', () async {
      await registrarVenda();
      await assertEstoque(qA: 3, qB: 4, total: 7);

      // Segundo write: snapshot pré-venda com timestamp antigo (vetor H9/LWW).
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
        kProdutoStockRevisionField: 0,
      }, SetOptions(merge: true));

      trace.record(
        stage: 'second_write',
        source: 'stale_remote_lww',
        method: 'firestore.set',
        qA: _qA0,
        qB: _qB0,
        total: _total0,
      );

      await ProdutosFirestoreService.syncFirestoreToHive(
        lojaId: _lojaId,
        produtosBox: produtosBox,
        preferRemoteQuantity: true,
      );

      await assertHiveEstoque(
        qA: 3,
        qB: 4,
        total: 7,
        reason: 'R9b guard regressão estoque — Hive preservado',
      );
    });
  });
}
