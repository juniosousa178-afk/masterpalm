// TYPEH1-1…12 — TypeError web em variações Firestore (H1 Brinco 7mm/cristal).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/firestore_dynamic_map.dart';
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

const _lojaId = 'nathy-pratas-e-folheados';

/// Simula payload Firestore web: mapas aninhados [Map<String, Object?>].
Map<String, Object?> _variacoesWebLike(int qtd) => <String, Object?>{
      '7mm': <String, Object?>{'cristal': qtd},
    };

Future<void> _seedBrincoWebLike(
  FakeFirebaseFirestore fs,
  Box<Produto> produtosBox, {
  required String pid,
  int qtd = 5,
}) async {
  await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .set({
    'nome': 'Brinco Brilhante Quadrado 7mm',
    'quantidade': qtd,
    'slug': pid,
    'variacoes': _variacoesWebLike(qtd),
    'estoquePorTamanho': <String, Object?>{'7mm': qtd},
  });
  await produtosBox.add(
    Produto.vazio()
      ..nome = 'Brinco Brilhante Quadrado 7mm'
      ..idFirebase = pid
      ..lojaId = _lojaId
      ..quantidade = qtd
      ..precoFinal = 39.90
      ..variacoes = {
        '7mm': {'cristal': qtd},
      }
      ..estoquePorTamanho = {'7mm': qtd},
  );
}

List<VendaItem> _itensH1(String pid) => [
      VendaItem(
        produtoNome: 'Brinco Brilhante Quadrado 7mm',
        quantidade: 1,
        precoUnitario: 39.90,
        productId: pid,
        tamanho: '7mm',
        cor: 'cristal',
      ),
    ];

Future<Map<String, dynamic>?> _marker(FakeFirebaseFirestore fs, String op) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_baixa_pagamento')
      .doc(op)
      .get();
  return snap.data();
}

Future<Map<String, dynamic>?> _intent(FakeFirebaseFirestore fs, String id) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('sale_intents')
      .doc(id)
      .get();
  return snap.data();
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
    hiveDir = await Directory.systemTemp.createTemp('hive_typeh1_');
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
    await Hive.close();
    try {
      await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    VendasService.debugOperacoesEmAndamentoClearForTests();
    SaleIntentService.debugClearOverride();
    VendaOperationJournalService.debugClearOverride();
    EstoqueTransactionService.debugClearOverrides();
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;

    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    SaleIntentService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_typeh1_$s');
    clientesBox = await Hive.openBox<Cliente>('c_typeh1_$s');
    vendasBox = await Hive.openBox<Venda>('v_typeh1_$s');
    journalBox = await Hive.openBox<Map>(
      HiveBoxNames.vendaOperationJournal(_lojaId),
    );
    await journalBox.clear();
    VendaOperationJournalService.debugBoxOverride = journalBox;
  });

  tearDown(() async {
    LojaAtivaResolver.debugResolveOverride = null;
    EstoqueTransactionService.debugClearOverrides();
    SaleIntentService.debugClearOverride();
    VendaOperationJournalService.debugClearOverride();
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    await produtosBox.close();
    await clientesBox.close();
    await vendasBox.close();
    if (Hive.isBoxOpen(HiveBoxNames.vendaOperationJournal(_lojaId))) {
      await journalBox.close();
    }
  });

  Future<Cliente> seedClienteH1() async {
    final c = Cliente(
      nome: 'Natalia Teste',
      telefone: '',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<Venda> registrarH1({
    required Cliente c,
    required String pid,
    required String intentId,
    double pix = 37.91,
  }) {
    return VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: c.nome,
      clienteExistente: c,
      itens: _itensH1(pid),
      pix: pix,
      lojaId: _lojaId,
      saleIntentId: intentId,
    );
  }

  group('TYPEH1 — runtime type H1 web', () {
    test('TYPEH1-12 cast legado falha com mapa dinâmico (interop web)', () {
      final raw = Map<dynamic, dynamic>.from({
        '7mm': Map<dynamic, dynamic>.from({'cristal': 3}),
      });
      expect(
        () => legacyUnsafeFirestoreVariacoesCast(raw),
        throwsA(isA<TypeError>()),
      );
      final norm = firestoreStringDynamicMapOrEmpty(raw);
      expect(norm['7mm'], isA<Map>());
      expect((norm['7mm'] as Map)['cristal'], 3);
    });

    test('TYPEH1-1 venda coordenada com variação web-like', () async {
      const pid = 'brinco-h1-1';
      const intentId = 'intent-typeh1-1';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final c = await seedClienteH1();
      final v = await registrarH1(c: c, pid: pid, intentId: intentId);
      expect(v.idFirebase, isNotEmpty);
      expect(vendasBox.length, 1);
    });

    test('TYPEH1-2 produto variação tam+cor debita remoto', () async {
      const pid = 'brinco-h1-2';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid, qtd: 3);
      final c = await seedClienteH1();
      await registrarH1(c: c, pid: pid, intentId: 'intent-typeh1-2');
      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 2);
      final variacoes = firestoreStringDynamicMapOrEmpty(snap.data()?['variacoes']);
      final tam = firestoreStringDynamicMapOrEmpty(variacoes['7mm']);
      expect(tam['cristal'], 2);
    });

    test('TYPEH1-3 Pix como pagamento', () async {
      const pid = 'brinco-h1-3';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final c = await seedClienteH1();
      final v = await registrarH1(c: c, pid: pid, intentId: 'intent-typeh1-3', pix: 37.91);
      expect(v.pagamentoPix, closeTo(37.91, 0.01));
    });

    test('TYPEH1-4 transaction batch idempotente sem TypeError', () async {
      const pid = 'brinco-h1-4';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final r = await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: [
          {
            'productId': pid,
            'nome': 'Brinco',
            'quantidade': 1,
            'tamanho': '7mm',
            'cor': 'cristal',
          },
        ],
        operationId: 'op-typeh1-4',
      );
      expect(r.status, EstoqueBaixaOperationStatus.applied);
    });

    test('TYPEH1-5 marker baixa após venda', () async {
      const pid = 'brinco-h1-5';
      const intentId = 'intent-typeh1-5';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final c = await seedClienteH1();
      final v = await registrarH1(c: c, pid: pid, intentId: intentId);
      final m = await _marker(firestore, v.idFirebase!);
      expect(m?['baixaAplicada'], isTrue);
    });

    test('TYPEH1-6 journal limpo após sucesso', () async {
      const pid = 'brinco-h1-6';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final c = await seedClienteH1();
      await registrarH1(c: c, pid: pid, intentId: 'intent-typeh1-6');
      expect(journalBox.isEmpty, isTrue);
    });

    test('TYPEH1-7 persist Hive venda', () async {
      const pid = 'brinco-h1-7';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final c = await seedClienteH1();
      await registrarH1(c: c, pid: pid, intentId: 'intent-typeh1-7');
      expect(vendasBox.length, 1);
    });

    test('TYPEH1-8 sale intent completed', () async {
      const intentId = 'intent-typeh1-8';
      const pid = 'brinco-h1-8';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid);
      final c = await seedClienteH1();
      await registrarH1(c: c, pid: pid, intentId: intentId);
      final doc = await _intent(firestore, intentId);
      expect(doc?['status'], 'completed');
    });

    test('TYPEH1-9 retry mesma saleIntent após sucesso é idempotente', () async {
      const pid = 'brinco-h1-9';
      const intentId = 'intent-typeh1-9';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid, qtd: 5);
      final c = await seedClienteH1();
      final itens = _itensH1(pid);
      final v1 = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: itens,
        pix: 37.91,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );
      final v2 = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: itens,
        pix: 37.91,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );
      expect(v2.idFirebase, v1.idFirebase);
      expect(vendasBox.length, 1);
    });

    test('TYPEH1-10 batch direto com variacoes web-like', () async {
      const pid = 'brinco-h1-10';
      await _seedBrincoWebLike(firestore, produtosBox, pid: pid, qtd: 2);
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: [
          {
            'productId': pid,
            'nome': 'Brinco',
            'quantidade': 1,
            'tamanho': '7mm',
            'cor': 'cristal',
          },
        ],
        operationId: 'op-typeh1-10',
      );
      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 1);
    });

    test('TYPEH1-11 produção não usa cast direto em variacoes batch', () {
      final src = File('lib/services/estoque_transaction_service.dart')
          .readAsStringSync();
      expect(
        src.contains("data['variacoes'] as Map<String, dynamic>?"),
        isFalse,
      );
      expect(src.contains('firestoreStringDynamicMapOrEmpty'), isTrue);
    });
  });
}
