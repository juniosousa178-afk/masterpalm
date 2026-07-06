// M3.2-C — order review + Sale Intent coordenado.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/order_review_sale_intent.dart';
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

const _lojaId = 'loja-m32c-order-review';
const _orderIdA = 'order-m32c-a';
const _orderIdB = 'order-m32c-b';

String _intentFor(String orderId) =>
    OrderReviewSaleIntent.saleIntentIdForOrder(orderId);

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
        produtoNome: 'Prod OR',
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
    hiveDir = await Directory.systemTemp.createTemp('hive_m32c_or_');
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
        .set({'nome': 'Prod OR', 'quantidade': qtd});
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Prod OR'
        ..idFirebase = pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 10,
    );
  }

  Future<Cliente> seedCliente() async {
    final c = Cliente(
      nome: 'Cli OR',
      telefone: '11',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<Venda> registrarOrderReview({
    required Cliente c,
    required String orderId,
    required List<VendaItem> itens,
    double dinheiro = 10,
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
      saleIntentId: _intentFor(orderId),
      saleIntentOrigin: SaleIntentOrigins.orderReview,
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
    produtosBox = await Hive.openBox<Produto>('p_or_$s');
    clientesBox = await Hive.openBox<Cliente>('c_or_$s');
    vendasBox = await Hive.openBox<Venda>('v_or_$s');
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

  group('M3.2-C order review + Sale Intent', () {
    test('OR-1 saleIntentId derivado do orderId', () {
      expect(_intentFor(_orderIdA), 'order_review:$_orderIdA');
      expect(
        OrderReviewSaleIntent.saleIntentIdForOrder(' x '),
        'order_review:x',
      );
    });

    test('OR-2 origin = order_review no doc remoto', () async {
      const pid = 'prod-or-2';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      await registrarOrderReview(
        c: c,
        orderId: _orderIdA,
        itens: _itens(pid),
      );
      final doc = await _saleIntent(firestore, _intentFor(_orderIdA));
      expect(doc!['origin'], SaleIntentOrigins.orderReview);
      expect(doc['status'], 'completed');
    });

    test('OR-3 mesmo orderId retry → mesmo operationId, 1 venda, 1 débito',
        () async {
      const pid = 'prod-or-3';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_orderIdA);
      final v1 = await registrarOrderReview(
        c: c,
        orderId: _orderIdA,
        itens: itens,
      );
      final op = (await _saleIntent(firestore, intentId))!['operationId'];
      final v2 = await registrarOrderReview(
        c: c,
        orderId: _orderIdA,
        itens: itens,
      );
      expect(v2.idFirebase, op);
      expect(v1.idFirebase, v2.idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('OR-4 orderIds diferentes → operationIds e vendas distintas', () async {
      const pid = 'prod-or-4';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itens(pid);
      final v1 = await registrarOrderReview(
        c: c,
        orderId: _orderIdA,
        itens: itens,
      );
      final v2 = await registrarOrderReview(
        c: c,
        orderId: _orderIdB,
        itens: itens,
      );
      expect(v1.idFirebase, isNot(v2.idFirebase));
      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, pid), 8);
    });

    test('OR-5 hash divergente mesmo orderId → conflito', () async {
      const pid = 'prod-or-5';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final intentId = _intentFor(_orderIdA);
      await registrarOrderReview(
        c: c,
        orderId: _orderIdA,
        itens: _itens(pid, qtd: 1),
      );
      final qtdAntes = await _qtdRemota(firestore, pid);
      await expectLater(
        registrarOrderReview(
          c: c,
          orderId: _orderIdA,
          itens: _itens(pid, qtd: 2),
        ),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
      expect(await _qtdRemota(firestore, pid), qtdAntes);
      expect(vendasBox.length, 1);
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'completed');
    });

    test('OR-6 falha após baixa antes de Hive → retry sem segundo débito', () async {
      const pid = 'prod-or-6';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_orderIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrarOrderReview(c: c, orderId: _orderIdA, itens: itens),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final mid = await _saleIntent(firestore, intentId);
      expect(mid!['status'], 'stock_applied');
      final op = mid['operationId'] as String;
      final v = await registrarOrderReview(c: c, orderId: _orderIdA, itens: itens);
      expect(v.idFirebase, op);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('OR-7 falha Hive + rollback OK → reverted + retry conclui', () async {
      const pid = 'prod-or-7';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_orderIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      await expectLater(
        registrarOrderReview(c: c, orderId: _orderIdA, itens: itens),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      expect(vendasBox, isEmpty);
      expect(await _qtdRemota(firestore, pid), 5);
      final rev = await _saleIntent(firestore, intentId);
      expect(rev!['status'], 'reverted');
      final op = rev['operationId'] as String;
      await registrarOrderReview(c: c, orderId: _orderIdA, itens: itens);
      expect(vendasBox.length, 1);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['status'], 'completed');
      expect(fin['operationId'], op);
    });

    test('OR-8 falha Hive + rollback FAIL → critical', () async {
      const pid = 'prod-or-8';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final intentId = _intentFor(_orderIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      VendasService.debugForcarFalhaEstornoPreHiveRollback = () async {
        throw Exception('estorno falhou');
      };
      await expectLater(
        registrarOrderReview(
          c: c,
          orderId: _orderIdA,
          itens: _itens(pid),
        ),
        throwsA(isA<VendaPersistenciaInconsistenciaCritica>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'critical');
    });

    test('OR-9 fiado N/A — order review não passa isFiado', () {
      final src = File('lib/screens/order_review_screen.dart').readAsStringSync();
      expect(src.contains('isFiado'), isFalse);
      expect(src.contains('dataVencimentoFiado'), isFalse);
    });

    test('OR-10 coalescência local — duplo submit mesmo orderId', () async {
      const pid = 'prod-or-10';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itens(pid);
      final f1 = registrarOrderReview(c: c, orderId: _orderIdA, itens: itens);
      final f2 = registrarOrderReview(c: c, orderId: _orderIdA, itens: itens);
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, results[1].idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 9);
    });

    test('OR-11 status pedido pós-venda — lacuna P2 documentada', () {
      final src = File('lib/screens/order_review_screen.dart').readAsStringSync();
      final iVenda = src.indexOf('registrarVendaMulti');
      final iStatus = src.indexOf("'status': 'concluido'");
      expect(iVenda, greaterThan(0));
      expect(iStatus, greaterThan(iVenda),
          reason: 'status concluido ocorre após venda; não transacional com baixa');
    });
  });
}
