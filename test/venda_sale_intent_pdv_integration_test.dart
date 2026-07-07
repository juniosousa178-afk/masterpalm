// M3.2-B — integração PDV manual + Sale Intent coordenado.

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

const _lojaId = 'loja-m32b-pdv';

Future<int> _qtdRemota(FakeFirebaseFirestore fs, String pid) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

Future<Map<String, dynamic>?> _marker(
  FakeFirebaseFirestore fs,
  String opId,
) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_baixa_pagamento')
      .doc(opId)
      .get();
  return snap.data();
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

List<VendaItem> _itensSimples(String pid, {int qtd = 1}) => [
      VendaItem(
        produtoNome: 'Prod',
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
    hiveDir = await Directory.systemTemp.createTemp('hive_m32b_');
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

  Future<void> seedProduto({required String pid, int qtd = 5}) async {
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

  Future<Cliente> seedCliente() async {
    final c = Cliente(
      nome: 'Cli M32B',
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
    bool isFiado = false,
    DateTime? vencimento,
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
      lojaId: _lojaId,
      isFiado: isFiado,
      dataVencimentoFiado: vencimento,
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
    produtosBox = await Hive.openBox<Produto>('p_m32b_$s');
    clientesBox = await Hive.openBox<Cliente>('c_m32b_$s');
    vendasBox = await Hive.openBox<Venda>('v_m32b_$s');
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

  group('M3.2-B PDV coordenado', () {
    test('M32B-1 reserveOrJoin antes da baixa', () async {
      const pid = 'prod-m32b-1';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-1';
      await registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId);
      final doc = await _saleIntent(firestore, intentId);
      expect(doc, isNotNull);
      expect(doc!['status'], 'completed');
      expect(doc['origin'], 'pdv_manual');
    });

    test('M32B-2 operationId reservation == journal operationId', () async {
      const pid = 'prod-m32b-2';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-2';
      final v = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      final intent = await _saleIntent(firestore, intentId);
      expect(v.idFirebase, intent!['operationId']);
    });

    test('M32B-3 operationId == venda.idFirebase', () async {
      const pid = 'prod-m32b-3';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-3';
      final v = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      final intent = await _saleIntent(firestore, intentId);
      expect(v.idFirebase, intent!['operationId']);
    });

    test('M32B-4 marker usa mesmo operationId', () async {
      const pid = 'prod-m32b-4';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-4';
      final v = await registrar(
        c: c,
        itens: _itensSimples(pid),
        saleIntentId: intentId,
      );
      final m = await _marker(firestore, v.idFirebase!);
      expect(m?['operationId'], v.idFirebase);
      expect(m?['baixaAplicada'], isTrue);
    });

    test('M32B-5 happy path state machine', () async {
      const pid = 'prod-m32b-5';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-5';
      await registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId);
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'completed');
    });

    test('M32B-6 retry pós-baixa crash — 1 débito 1 venda', () async {
      const pid = 'prod-m32b-6';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      const intentId = 'intent-m32b-6';
      final itens = _itensSimples(pid);
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrar(c: c, itens: itens, saleIntentId: intentId),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final intentMid = await _saleIntent(firestore, intentId);
      expect(intentMid!['status'], 'stock_applied');
      final opId = intentMid['operationId'] as String;
      final v = await registrar(c: c, itens: itens, saleIntentId: intentId);
      expect(v.idFirebase, opId);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('M32B-7 retry pós-Hive antes de complete', () async {
      const pid = 'prod-m32b-7';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      const intentId = 'intent-m32b-7';
      final itens = _itensSimples(pid);
      VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete =
          () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrar(c: c, itens: itens, saleIntentId: intentId),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete = null;
      expect(vendasBox.length, 1);
      final intentMid = await _saleIntent(firestore, intentId);
      expect(intentMid!['status'], 'sale_persisted');
      final v2 = await registrar(c: c, itens: itens, saleIntentId: intentId);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
      final intentFinal = await _saleIntent(firestore, intentId);
      expect(intentFinal!['status'], 'completed');
      expect(v2.idFirebase, intentFinal['operationId']);
    });

    test('M32B-8 hash divergente fail-closed', () async {
      const pid = 'prod-m32b-8';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-8';
      await registrar(c: c, itens: _itensSimples(pid), saleIntentId: intentId);
      final qtdAntes = await _qtdRemota(firestore, pid);
      await expectLater(
        registrar(
          c: c,
          itens: _itensSimples(pid, qtd: 2),
          saleIntentId: intentId,
        ),
        throwsA(isA<SaleIntentIdentityConflictException>()),
      );
      expect(await _qtdRemota(firestore, pid), qtdAntes);
      expect(vendasBox.length, 1);
    });

    test('M32B-9 journal operationId divergente fail-closed', () async {
      const pid = 'prod-m32b-9';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-9';
      final itens = _itensSimples(pid);
      final txItems = [
        {'productId': pid, 'nome': 'Prod', 'quantidade': 1},
      ];
      final hash =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(txItems);
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
        registrar(c: c, itens: itens, saleIntentId: intentId),
        throwsA(isA<VendaOperationJournalIdentityConflictException>()),
      );
      expect(vendasBox, isEmpty);
    });

    test('M32B-10 duas intents mesmo conteúdo → duas vendas', () async {
      const pid = 'prod-m32b-10';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itensSimples(pid);
      final v1 = await registrar(
        c: c,
        itens: itens,
        saleIntentId: 'intent-m32b-10a',
      );
      final v2 = await registrar(
        c: c,
        itens: itens,
        saleIntentId: 'intent-m32b-10b',
      );
      expect(v1.idFirebase, isNot(v2.idFirebase));
      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, pid), 8);
    });

    test('M32B-11 falha Hive + rollback OK → reverted', () async {
      const pid = 'prod-m32b-11';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      const intentId = 'intent-m32b-11';
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      await expectLater(
        registrar(
          c: c,
          itens: _itensSimples(pid),
          saleIntentId: intentId,
        ),
        throwsA(isA<Exception>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      expect(vendasBox, isEmpty);
      expect(await _qtdRemota(firestore, pid), 5);
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'reverted');
    });

    test('M32B-12 rollback FAIL → critical', () async {
      const pid = 'prod-m32b-12';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      const intentId = 'intent-m32b-12';
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw Exception('hive add falhou');
      };
      VendasService.debugForcarFalhaEstornoPreHiveRollback = () async {
        throw Exception('estorno falhou');
      };
      await expectLater(
        registrar(
          c: c,
          itens: _itensSimples(pid),
          saleIntentId: intentId,
        ),
        throwsA(isA<VendaPersistenciaInconsistenciaCritica>()),
      );
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'critical');
    });

    test('M32B-13 fiado happy path completed', () async {
      const pid = 'prod-m32b-13';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      const intentId = 'intent-m32b-13';
      await registrar(
        c: c,
        itens: _itensSimples(pid),
        dinheiro: 0,
        isFiado: true,
        vencimento: DateTime.now().add(const Duration(days: 30)),
        saleIntentId: intentId,
      );
      expect(vendasBox.length, 1);
      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(_lojaId),
      );
      expect(crBox.length, greaterThan(0));
      await crBox.close();
      final doc = await _saleIntent(firestore, intentId);
      expect(doc!['status'], 'completed');
    });

    test('M32B-15 complete remoto falha — retry converge', () async {
      const pid = 'prod-m32b-15';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      const intentId = 'intent-m32b-15';
      final itens = _itensSimples(pid);
      SaleIntentService.debugThrowOnComplete = true;
      final v1 = await registrar(
        c: c,
        itens: itens,
        saleIntentId: intentId,
      );
      SaleIntentService.debugThrowOnComplete = false;
      expect(vendasBox.length, 1);
      final mid = await _saleIntent(firestore, intentId);
      expect(mid!['status'], 'sale_persisted');
      final v2 = await registrar(c: c, itens: itens, saleIntentId: intentId);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
      final fin = await _saleIntent(firestore, intentId);
      expect(fin!['status'], 'completed');
      expect(v2.idFirebase, v1.idFirebase);
    });

    test('M32B-16 legado sem saleIntentId preservado', () async {
      const pid = 'prod-m32b-16';
      await seedProduto(pid: pid, qtd: 5);
      final c = await seedCliente();
      final v = await registrar(c: c, itens: _itensSimples(pid));
      expect(v.idFirebase, isNotEmpty);
      expect(await _saleIntent(firestore, v.idFirebase!), isNull);
    });

    test('M32B coalesce — mesma intent concorrente', () async {
      const pid = 'prod-m32b-coalesce';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      const intentId = 'intent-coalesce';
      final itens = _itensSimples(pid);
      final f1 = registrar(c: c, itens: itens, saleIntentId: intentId);
      final f2 = registrar(c: c, itens: itens, saleIntentId: intentId);
      final results = await Future.wait([f1, f2]);
      expect(results[0].idFirebase, results[1].idFirebase);
      expect(vendasBox.length, 1);
    });
  });
}
