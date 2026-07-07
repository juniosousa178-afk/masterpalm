// M3.7-HOTFIX — identidade journal × Sale Intent (JID-1…JID-12).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
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

const _lojaId = 'loja-jid-identity';

List<Map<String, dynamic>> _txItems(String pid, {int qtd = 1}) => [
      {'productId': pid, 'nome': 'Prod', 'quantidade': qtd},
    ];

List<VendaItem> _itensSimples(String pid, {int qtd = 1}) => [
      VendaItem(
        produtoNome: 'Prod',
        quantidade: qtd,
        precoUnitario: 10,
        productId: pid,
      ),
    ];

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

Future<int> _qtdRemota(FakeFirebaseFirestore fs, String pid) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late Directory hiveDir;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;
  late Box<Map> journalBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_jid_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
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
        .set({'nome': 'Prod', 'quantidade': qtd});
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Prod'
        ..idFirebase = pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 10,
    );
  }

  Future<Cliente> seedCliente({String nome = 'Cli JID'}) async {
    final c = Cliente(
      nome: nome,
      telefone: '11',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<Venda> registrar({
    required Cliente c,
    required List<VendaItem> itens,
    double dinheiro = 10,
    double pix = 0,
    double cartao = 0,
    bool isFiado = false,
    String? saleIntentId,
  }) {
    return VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: c.nome,
      clienteExistente: c,
      itens: itens,
      dinheiro: dinheiro,
      pix: pix,
      cartao: cartao,
      lojaId: _lojaId,
      isFiado: isFiado,
      saleIntentId: saleIntentId,
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
    produtosBox = await Hive.openBox<Produto>('p_jid_$s');
    clientesBox = await Hive.openBox<Cliente>('c_jid_$s');
    vendasBox = await Hive.openBox<Venda>('v_jid_$s');
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

  group('JID — journal identity', () {
    test('JID-1 venda simples primeira tentativa', () async {
      const pid = 'prod-jid-1';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-jid-1';
      final v = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      expect(v.idFirebase, isNotEmpty);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 9);
      final intent = await _saleIntent(firestore, intentId);
      expect(intent!['status'], 'completed');
      expect(v.idFirebase, intent['operationId']);
    });

    test('JID-2 retry mesma intenção após interrupt', () async {
      const pid = 'prod-jid-2';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-jid-2';
      VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete =
          () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete = null;
      final v2 = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      expect(vendasBox.length, 1);
      final intent = await _saleIntent(firestore, intentId);
      expect(intent!['status'], 'completed');
      expect(v2.idFirebase, intent['operationId']);
    });

    test('JID-3 duas vendas distintas mesmo carrinho', () async {
      const pid = 'prod-jid-3';
      await seedProduto(pid: pid, qtd: 20);
      final c = await seedCliente();
      final itens = _itensSimples(pid);
      final v1 = await registrar(
        c: c,
        itens: itens,
        saleIntentId: 'intent-jid-3a',
      );
      final v2 = await registrar(
        c: c,
        itens: itens,
        saleIntentId: 'intent-jid-3b',
      );
      expect(v1.idFirebase, isNot(v2.idFirebase));
      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, pid), 18);
    });

    test('JID-4 journal legado hash-only não bloqueia venda coordenada', () async {
      const pid = 'prod-jid-4';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-jid-4';
      final itens = _itensSimples(pid);
      final hash = EstoqueTransactionService.computeTxItemsHashForIdempotencia(
        _txItems(pid),
      );
      final legacyKey = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      await journalBox.put(legacyKey, {
        'operationId': '00000000-0000-4000-8000-000000000099',
        'lojaId': _lojaId,
        'operationKey': legacyKey,
        'stockEffectHash': hash,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'critical': false,
      });
      final v = await registrar(
        c: c,
        itens: itens,
        saleIntentId: intentId,
      );
      expect(v.idFirebase, isNot('00000000-0000-4000-8000-000000000099'));
      expect(vendasBox.length, 1);
    });

    test('JID-5 sale intent reserved → venda completa', () async {
      const pid = 'prod-jid-5';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-jid-5';
      final hash = EstoqueTransactionService.computeTxItemsHashForIdempotencia(
        _txItems(pid),
      );
      await SaleIntentService.reserveOrJoin(
        lojaId: _lojaId,
        saleIntentId: intentId,
        origin: 'pdv_manual',
        stockEffectHash: hash,
      );
      final mid = await _saleIntent(firestore, intentId);
      expect(mid!['status'], 'reserved');
      await registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['status'], 'completed');
    });

    test('JID-6 sale intent completed → join idempotente', () async {
      const pid = 'prod-jid-6';
      await seedProduto(pid: pid, qtd: 8);
      final c = await seedCliente();
      const intentId = 'intent-jid-6';
      final v1 = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      final v2 = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      expect(identical(v1, v2) || v1.idFirebase == v2.idFirebase, isTrue);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 7);
    });

    test('JID-7 reverted → reserved retry', () async {
      const pid = 'prod-jid-7';
      await seedProduto(pid: pid, qtd: 6);
      final c = await seedCliente();
      const intentId = 'intent-jid-7';
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      await expectLater(
        registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final reverted = await _saleIntent(firestore, intentId);
      expect(reverted!['status'], 'reverted');
      final opId = reverted['operationId']?.toString();
      final v = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      expect(v.idFirebase, opId);
      expect(await _qtdRemota(firestore, pid), 5);
    });

    test('JID-8 dois cliques coalesce mesma intenção', () async {
      const pid = 'prod-jid-8';
      await seedProduto(pid: pid, qtd: 12);
      final c = await seedCliente();
      const intentId = 'intent-jid-8';
      final itens = _itensSimples(pid);
      final f1 = registrar(c: c, itens: itens, saleIntentId: intentId);
      final f2 = registrar(c: c, itens: itens, saleIntentId: intentId);
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, results[1].idFirebase);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 11);
    });

    test('JID-9 concorrência dois intents distintos mesmo carrinho', () async {
      const pid = 'prod-jid-9';
      await seedProduto(pid: pid, qtd: 15);
      final c = await seedCliente();
      final itens = _itensSimples(pid);
      final f1 = registrar(
        c: c,
        itens: itens,
        saleIntentId: 'intent-jid-9a',
      );
      final f2 = registrar(
        c: c,
        itens: itens,
        saleIntentId: 'intent-jid-9b',
      );
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, isNot(results[1].idFirebase));
      expect(vendasBox.length, 2);
    });

    test('JID-10 forma de pagamento diferente não colide journal', () async {
      const pid = 'prod-jid-10';
      await seedProduto(pid: pid, qtd: 20);
      final c = await seedCliente();
      final itens = _itensSimples(pid);
      await registrar(
        c: c,
        itens: itens,
        dinheiro: 10,
        saleIntentId: 'intent-jid-10a',
      );
      await registrar(
        c: c,
        itens: itens,
        pix: 10,
        saleIntentId: 'intent-jid-10b',
      );
      expect(vendasBox.length, 2);
    });

    test('JID-11 quantidade diferente gera hash distinto', () async {
      const pid = 'prod-jid-11';
      await seedProduto(pid: pid, qtd: 20);
      final c = await seedCliente();
      await registrar(
        c: c,
        itens: _itensSimples(pid, qtd: 1),
        saleIntentId: 'intent-jid-11a',
      );
      await registrar(
        c: c,
        itens: _itensSimples(pid, qtd: 2),
        saleIntentId: 'intent-jid-11b',
      );
      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, pid), 17);
    });

    test('JID-12 cliente diferente mesmo carrinho', () async {
      const pid = 'prod-jid-12';
      await seedProduto(pid: pid, qtd: 20);
      final c1 = await seedCliente(nome: 'Cli A');
      final c2 = await seedCliente(nome: 'Cli B');
      final itens = _itensSimples(pid);
      await registrar(
        c: c1,
        itens: itens,
        saleIntentId: 'intent-jid-12a',
      );
      await registrar(
        c: c2,
        itens: itens,
        saleIntentId: 'intent-jid-12b',
      );
      expect(vendasBox.length, 2);
    });

    test('JID-RED operationId divergente na mesma intenção fail-closed', () async {
      const pid = 'prod-jid-red';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-jid-red';
      final hash = EstoqueTransactionService.computeTxItemsHashForIdempotencia(
        _txItems(pid),
      );
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
        saleIntentId: intentId,
      );
      await journalBox.put(key, {
        'operationId': '00000000-0000-4000-8000-000000000099',
        'lojaId': _lojaId,
        'operationKey': key,
        'stockEffectHash': hash,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'critical': false,
      });
      await expectLater(
        registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId),
        throwsA(isA<VendaOperationJournalIdentityConflictException>()),
      );
      expect(vendasBox, isEmpty);
    });
  });
}
