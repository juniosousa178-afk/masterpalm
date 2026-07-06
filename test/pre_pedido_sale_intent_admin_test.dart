// M3.3 — fluxo operacional admin (pre_pedidos) + Sale Intent coordenado.

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

const _lojaId = 'loja-m33-admin-pre-pedido';
const _pedidoIdA = 'pre-pedido-admin-a';

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
    hiveDir = await Directory.systemTemp.createTemp('hive_m33_admin_');
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

  Future<Venda> registrarAdminPrePedido({
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
    produtosBox = await Hive.openBox<Produto>('p_admin_$s');
    clientesBox = await Hive.openBox<Cliente>('c_admin_$s');
    vendasBox = await Hive.openBox<Venda>('v_admin_$s');
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

  group('M3.3 admin pre_pedidos + Sale Intent', () {
    test('ADMIN-1 saleIntentId derivado do prePedidoId', () {
      expect(_intentFor(_pedidoIdA), 'pre_pedido:$_pedidoIdA');
      expect(
        PrePedidoSaleIntent.saleIntentIdForPedido(' x '),
        'pre_pedido:x',
      );
    });

    test('ADMIN-2 origin = pre_pedido no doc remoto', () async {
      const pid = 'prod-pp-2';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: _itens(pid),
      );
      final doc = await _saleIntent(firestore, _intentFor(_pedidoIdA));
      expect(doc!['origin'], SaleIntentOrigins.prePedido);
      expect(doc['status'], 'completed');
    });

    test('ADMIN-3 mesmo pedidoId retry → mesmo operationId, 1 venda, 1 débito',
        () async {
      const pid = 'prod-pp-3';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      final v1 = await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final op = (await _saleIntent(firestore, intentId))!['operationId'];
      final v2 = await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      expect(v2.idFirebase, op);
      expect(v1.idFirebase, v2.idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('ADMIN-4 duas confirmações mesmo prePedido → 1 venda, 1 baixa',
        () async {
      const pid = 'prod-admin-4';
      await seedProduto(pid: pid, qtd: 8);
      final c = await seedCliente();
      final itens = _itens(pid);
      await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 7);
    });

    test('ADMIN-5 dois operadores mesmo prePedido → mesmo operationId', () async {
      const pid = 'prod-admin-5';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itens(pid);
      final f1 = registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final f2 = registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, results[1].idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 9);
    });

    test('ADMIN-6 hash divergente mesmo prePedidoId → conflito', () async {
      const pid = 'prod-pp-5';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final intentId = _intentFor(_pedidoIdA);
      await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: _itens(pid, qtd: 1),
      );
      final qtdAntes = await _qtdRemota(firestore, pid);
      await expectLater(
        registrarAdminPrePedido(
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

    test('ADMIN-7 rollback OK → reverted + retry conclui', () async {
      const pid = 'prod-pp-7';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      await expectLater(
        registrarAdminPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      expect(vendasBox, isEmpty);
      expect(await _qtdRemota(firestore, pid), 5);
      final rev = await _saleIntent(firestore, intentId);
      expect(rev!['status'], 'reverted');
      final op = rev['operationId'] as String;
      await registrarAdminPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      expect(vendasBox.length, 1);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['status'], 'completed');
      expect(fin['operationId'], op);
    });

    test('ADMIN-8 critical bloqueia nova reserva', () async {
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
        registrarAdminPrePedido(
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
        registrarAdminPrePedido(
          c: c,
          pedidoId: _pedidoIdA,
          itens: _itens(pid),
        ),
        throwsA(isA<SaleIntentCriticalStateException>()),
      );
    });

    test('ADMIN-9 completed → join sem segundo débito', () async {
      const pid = 'prod-admin-9';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      final v1 = await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final op = (await _saleIntent(firestore, intentId))!['operationId'];
      final v2 = await registrarAdminPrePedido(
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

    test('ADMIN-10 alreadyApplied — replay operationId não duplica baixa',
        () async {
      const pid = 'prod-admin-10';
      await seedProduto(pid: pid, qtd: 6);
      final c = await seedCliente();
      final itens = _itens(pid);
      final v = await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final op = v.idFirebase!;
      final r2 = await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: [
          {
            'productId': pid,
            'nome': 'Prod PP',
            'quantidade': 1,
          },
        ],
        operationId: op,
      );
      expect(r2.baixaJaAplicadaAnteriormente, isTrue);
      expect(await _qtdRemota(firestore, pid), 5);
    });

    test('ADMIN-11 retry após reverted reutiliza operationId', () async {
      const pid = 'prod-pp-12';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      final intentId = _intentFor(_pedidoIdA);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('falha hive');
      };
      await expectLater(
        registrarAdminPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final rev = await _saleIntent(firestore, intentId);
      final opRev = rev!['operationId'] as String;
      final v = await registrarAdminPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      expect(v.idFirebase, opRev);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['operationId'], opRev);
      expect(fin['status'], 'completed');
    });

    test('ADMIN-12 retry após completed → join sem segundo débito', () async {
      const pid = 'prod-admin-12';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final itens = _itens(pid);
      await registrarAdminPrePedido(c: c, pedidoId: _pedidoIdA, itens: itens);
      final qtd = await _qtdRemota(firestore, pid);
      final v2 = await registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), qtd);
      expect(v2.idFirebase, isNotEmpty);
    });

    test('ADMIN-13 coalescência intent:pre_pedido:{id}', () async {
      const pid = 'prod-admin-13';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itens(pid);
      final f1 = registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final f2 = registrarAdminPrePedido(
        c: c,
        pedidoId: _pedidoIdA,
        itens: itens,
      );
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, results[1].idFirebase);
      expect(vendasBox.length, 1);
    });

    test('ADMIN-14 status pedido — confirmado após venda, antes do pós-pagamento',
        () {
      final src =
          File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      final iVenda = src.indexOf('VendasService.registrarVendaMulti');
      final iConfirmar = src.indexOf('PrePedidoService.confirmarPrePedido');
      final iPos = src.indexOf('PosPagamentoService.processarConfirmacaoPagamento');
      expect(iVenda, greaterThan(0));
      expect(iConfirmar, greaterThan(iVenda));
      expect(iPos, greaterThan(iConfirmar));
      expect(src, contains('PrePedidoSaleIntent.saleIntentIdForPedido'));
      expect(src, contains('estoqueJaBaixado: true'));
    });

    test('ADMIN-15 fiado N/A — admin pre_pedidos não passa isFiado', () {
      final src =
          File('lib/screens/pre_pedidos_screen.dart').readAsStringSync();
      final bloco = src.indexOf('Future<void> _confirmarPedido');
      expect(bloco, greaterThan(0));
      final trecho = src.substring(bloco, bloco + 4000);
      expect(trecho.contains('isFiado'), isFalse);
      expect(trecho.contains('dataVencimentoFiado'), isFalse);
    });
  });
}
