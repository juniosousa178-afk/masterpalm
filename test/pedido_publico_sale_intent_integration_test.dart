// M3.2-D — pedido público + Sale Intent coordenado.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/pre_pedido_sale_intent.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sale_intent_service.dart';
import 'package:master_palm/services/venda_operation_journal_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-m32d-pre-pedido';
const _pedidoIdA = 'pre-pedido-m32d-a';
const _pedidoIdB = 'pre-pedido-m32d-b';

String _intentFor(String pedidoId) =>
    PrePedidoSaleIntent.saleIntentIdForPedido(pedidoId);

Future<int> _qtdRemota(FakeFirebaseFirestore fs, String pid) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

Future<Map<String, dynamic>?> _saleIntent(
  FakeFirebaseFirestore fs,
  String intentId,
) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('sale_intents')
      .doc(intentId)
      .get();
  return snap.data();
}

List<VendaItem> _itens(String pid, {int qtd = 1}) => [
      VendaItem(
        produtoNome: 'Prod PP',
        quantidade: qtd,
        precoUnitario: 10,
        productId: pid,
      ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late Directory hiveDir;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;
  late Box<Map> journalBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_m32d_pp_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
  });

  tearDownAll(() async {
    SaleIntentService.debugClearOverride();
    VendaOperationJournalService.debugClearOverride();
    await Hive.close();
    try {
      await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> seedProduto({required String pid, int qtd = 10}) async {
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({'nome': 'Prod PP', 'quantidade': qtd});
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Prod PP'
        ..idFirebase = pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 10,
    );
  }

  Future<Cliente> seedCliente() async {
    final c = Cliente(
      nome: 'Cli PP',
      telefone: '11',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<Venda> registrarPrePedido({
    required Cliente c,
    required String pedidoId,
    required List<VendaItem> itens,
    double dinheiro = 10,
    bool isFiado = false,
    DateTime? vencimento,
  }) {
    return VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: c.nome,
      clienteExistente: c,
      itens: itens,
      dinheiro: dinheiro,
      lojaId: _lojaId,
      isFiado: isFiado,
      dataVencimentoFiado: vencimento,
      saleIntentId: _intentFor(pedidoId),
      saleIntentOrigin: PrePedidoSaleIntent.origin,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    VendasService.debugOperacoesEmAndamentoClearForTests();
    VendasService.debugVendasBoxAddOverride = null;
    VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
    VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
    VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete = null;
    SaleIntentService.debugClearOverride();
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    SaleIntentService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_pp_$s');
    clientesBox = await Hive.openBox<Cliente>('c_pp_$s');
    vendasBox = await Hive.openBox<Venda>('v_pp_$s');
    journalBox = await Hive.openBox<Map>(
      HiveBoxNames.vendaOperationJournal(_lojaId),
    );
    await journalBox.clear();
    VendaOperationJournalService.debugBoxOverride = journalBox;
  });

  tearDown(() async {
    SaleIntentService.debugClearOverride();
    VendaOperationJournalService.debugClearOverride();
    LojaAtivaResolver.debugResolveOverride = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await produtosBox.close();
    await clientesBox.close();
    await vendasBox.close();
    if (Hive.isBoxOpen(HiveBoxNames.vendaOperationJournal(_lojaId))) {
      await journalBox.close();
    }
  });

  group('M3.2-D pedido público + Sale Intent', () {
    test('PP-1 saleIntentId derivado do pedidoId', () {
      expect(_intentFor(_pedidoIdA), 'pre_pedido:$_pedidoIdA');
      expect(
        PrePedidoSaleIntent.saleIntentIdForPedido(' x '),
        'pre_pedido:x',
      );
    });

    test('PP-2 origin = pre_pedido no doc remoto', () async {
      const pid = 'prod-pp-2';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: _itens(pid),
      );
      final doc = await _saleIntent(firestore, _intentFor(_pedidoIdA));
      expect(doc!['origin'], SaleIntentOrigins.prePedido);
      expect(doc['status'], 'completed');
    });

    test('PP-3 mesmo pedidoId retry → mesmo operationId, 1 venda, 1 débito',
        () async {
      const pid = 'prod-pp-3';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      final v1 = await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final op = (await _saleIntent(firestore, intentId))!['operationId'];
      final v2 = await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      expect(v2.idFirebase, op);
      expect(v1.idFirebase, v2.idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('PP-4 pedidos diferentes → operationIds e vendas distintas', () async {
      const pid = 'prod-pp-4';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itens(pid);
      final v1 = await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final v2 = await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdB,
        itens: itens,
      );
      expect(v1.idFirebase, isNot(v2.idFirebase));
      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, pid), 8);
    });

    test('PP-5 hash divergente mesmo pedidoId → conflito', () async {
      const pid = 'prod-pp-5';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final intentId = _intentFor(_pedidoIdA);
      await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: _itens(pid, qtd: 1),
      );
      final qtdAntes = await _qtdRemota(firestore, pid);
      await expectLater(
        registrarPrePedido(
          c: c,
          pedidoId: _pedidoIdA,
          itens: _itens(pid, qtd: 2),
        ),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
      expect(await _qtdRemota(firestore, pid), qtdAntes);
      expect(vendasBox.length, 1);
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'completed');
    });

    test('PP-6 falha após baixa antes de Hive → retry sem segundo débito', () async {
      const pid = 'prod-pp-6';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final mid = await _saleIntent(firestore, intentId);
      expect(mid!['status'], 'stock_applied');
      final op = mid['operationId'] as String;
      final v = await registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      expect(v.idFirebase, op);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('PP-7 falha Hive + rollback OK → reverted + retry conclui', () async {
      const pid = 'prod-pp-7';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      await expectLater(
        registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      expect(vendasBox, isEmpty);
      expect(await _qtdRemota(firestore, pid), 5);
      final rev = await _saleIntent(firestore, intentId);
      expect(rev!['status'], 'reverted');
      final op = rev['operationId'] as String;
      await registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      expect(vendasBox.length, 1);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['status'], 'completed');
      expect(fin['operationId'], op);
    });

    test('PP-8 falha Hive + rollback FAIL → critical', () async {
      const pid = 'prod-pp-8';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      VendasService.debugForcarFalhaEstornoPreHiveRollback = () async {
        throw Exception('estorno falhou');
      };
      await expectLater(
        registrarPrePedido(
          c: c,
          pedidoId: _pedidoIdA,
          itens: _itens(pid),
        ),
        throwsA(isA<VendaPersistenciaInconsistenciaCritica>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'critical');
    });

    test('PP-9 fiado N/A — pedido público legado não passa isFiado', () {
      final src =
          File('lib/screens/pedido_publico_screen.dart').readAsStringSync();
      final blocoConfirmar = src.indexOf('Future<void> _confirmarPedido');
      expect(blocoConfirmar, greaterThan(0));
      final trecho = src.substring(blocoConfirmar, blocoConfirmar + 2500);
      expect(trecho.contains('isFiado'), isFalse);
      expect(trecho.contains('dataVencimentoFiado'), isFalse);
    });

    test('PP-10 coalescência local — duplo submit mesmo pedidoId', () async {
      const pid = 'prod-pp-10';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itens(pid);
      final f1 = registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      final f2 = registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, results[1].idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 9);
    });

    test('PP-11 status pedido pós-venda — lacuna P2 documentada', () {
      final src =
          File('lib/screens/pedido_publico_screen.dart').readAsStringSync();
      final iVenda = src.indexOf('registrarVendaMulti');
      final iStatus = src.indexOf("'status': 'confirmado'");
      expect(iVenda, greaterThan(0));
      expect(iStatus, greaterThan(iVenda),
          reason:
              'status confirmado em pre_pedidos ocorre após venda; não transacional');
    });

    test('PP-12 retry após reverted reutiliza operationId', () async {
      const pid = 'prod-pp-12';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('falha hive');
      };
      await expectLater(
        registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final rev = await _saleIntent(firestore, intentId);
      final opRev = rev!['operationId'] as String;
      final v = await registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      expect(v.idFirebase, opRev);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['operationId'], opRev);
      expect(fin['status'], 'completed');
    });

    test('PP-13 retry após completed → join sem segundo débito', () async {
      const pid = 'prod-pp-13';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      final v1 = await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final op = (await _saleIntent(firestore, intentId))!['operationId'];
      final v2 = await registrarPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      expect(v2.idFirebase, op);
      expect(v1.idFirebase, v2.idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
      expect((await _saleIntent(firestore, intentId))!['status'], 'completed');
    });

    test('PP-14 critical bloqueia nova reserva', () async {
      const pid = 'prod-pp-14';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      VendasService.debugForcarFalhaEstornoPreHiveRollback = () async {
        throw Exception('estorno falhou');
      };
      await expectLater(
        registrarPrePedido(
          c: c,
          pedidoId: _pedidoIdA,
          itens: _itens(pid),
        ),
        throwsA(isA<VendaPersistenciaInconsistenciaCritica>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'critical');
      await expectLater(
        registrarPrePedido(
          c: c,
          pedidoId: _pedidoIdA,
          itens: _itens(pid),
        ),
        throwsA(isA<SaleIntentCriticalStateException>()),
      );
    });

    test('PP-15 operationId preservado em stock_applied → retry → completed',
        () async {
      const pid = 'prod-pp-15';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final mid = await _saleIntent(firestore, intentId);
      final opMid = mid!['operationId'] as String;
      await registrarPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['operationId'], opMid);
      expect(fin['status'], 'completed');
      expect(vendasBox.values.single.idFirebase, opMid);
    });
  });
}
