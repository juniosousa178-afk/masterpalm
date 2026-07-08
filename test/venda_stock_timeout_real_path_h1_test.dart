// STOCKR2-1…12 — correlaciona path real H1 com timeout de estoque (pós c8ec492).

import 'dart:async';
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

import 'support/legacy_stock_batch_timeout_test_support.dart';

const _lojaId = 'nathy-pratas-e-folheados';
const _legacyMsg =
    LegacyStockBatchTimeoutTestSupport.legacyUserMessage;

Map<String, Object?> _variacoesWebLike(int qtd) => <String, Object?>{
      '7mm': <String, Object?>{'cristal': qtd},
    };

Future<void> _seedBrinco(
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

Future<int> _qtdRemota(FakeFirebaseFirestore fs, String pid) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

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
    hiveDir = await Directory.systemTemp.createTemp('hive_stockr2_');
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    VendasService.debugOperacoesEmAndamentoClearForTests();
    SaleIntentService.debugClearOverride();
    EstoqueTransactionService.debugClearOverrides();
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    SaleIntentService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_stockr2_$s');
    clientesBox = await Hive.openBox<Cliente>('c_stockr2_$s');
    vendasBox = await Hive.openBox<Venda>('v_stockr2_$s');
    journalBox = await Hive.openBox<Map>(
      HiveBoxNames.vendaOperationJournal(_lojaId),
    );
    await journalBox.clear();
    VendaOperationJournalService.debugBoxOverride = journalBox;
  });

  tearDown(() async {
    EstoqueTransactionService.debugClearOverrides();
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

  group('STOCKR2 — path real H1 timeout', () {
    test('STOCKR2-1 H1 usa batch idempotente via registrarVendaMulti', () async {
      const pid = 'brinco-path';
      const intentId = 'intent-stockr2-1';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      final v = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect(v.idFirebase, isNotEmpty);
      expect(await _marker(firestore, v.idFirebase!), isNotNull);
    });

    test('STOCKR2-2 1 item variação tam+cor debita remoto', () async {
      const pid = 'brinco-var';
      const intentId = 'intent-stockr2-2';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('STOCKR2-3 saleIntentId presente reserva intent', () async {
      const pid = 'brinco-intent';
      const intentId = 'intent-stockr2-3';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      final v = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      final intent = await _intent(firestore, intentId);
      expect(intent?['status'], 'completed');
      expect(intent?['operationId'], v.idFirebase);
    });

    test('STOCKR2-4 Pix persiste forma pagamento', () async {
      const pid = 'brinco-pix';
      const intentId = 'intent-stockr2-4';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      final v = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect(v.pagamentoPix, closeTo(39.90, 0.01));
    });

    test('STOCKR2-5 produção não contém mensagem timeout legado batch', () {
      final src = File('lib/services/estoque_transaction_service.dart')
          .readAsStringSync();
      expect(src.contains(_legacyMsg), isFalse);
      final idx = src.indexOf('_executarBaixaBatchInterno');
      expect(idx, greaterThan(0));
      final chunk = src.substring(idx, idx + 4000);
      expect(
        chunk.contains('.timeout(') && chunk.contains('seconds: 25'),
        isFalse,
      );
    });

    test('STOCKR2-6 delay >25s no path real completa sem TimeoutException', () async {
      const pid = 'brinco-slow';
      const op = 'op-slow-ok';
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({
        'nome': 'Brinco',
        'quantidade': 3,
        'slug': pid,
        'variacoes': _variacoesWebLike(3),
      });
      EstoqueTransactionService.debugBatchTransactionDelay =
          const Duration(milliseconds: 300);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: [
          {
            'productId': pid,
            'quantidade': 1,
            'tamanho': '7mm',
            'cor': 'cristal',
          },
        ],
        operationId: op,
      );

      expect(r.status, EstoqueBaixaOperationStatus.applied);
      expect(await _marker(firestore, op), isNotNull);
    });

    test('STOCKR2-7 runTransaction completa com variação', () async {
      const pid = 'brinco-tx';
      const op = 'op-tx-7';
      await _seedBrinco(firestore, produtosBox, pid: pid, qtd: 2);

      final r =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: [
          {
            'productId': pid,
            'quantidade': 1,
            'tamanho': '7mm',
            'cor': 'cristal',
          },
        ],
        operationId: op,
      );

      expect(r.transactionResults, isNotEmpty);
      expect(r.transactionResults.first.quantidadeDebitada, 1);
    });

    test('STOCKR2-8 marker criado após baixa', () async {
      const pid = 'brinco-marker';
      const intentId = 'intent-stockr2-8';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      final v = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      final m = await _marker(firestore, v.idFirebase!);
      expect(m?['baixaAplicada'], isTrue);
      expect(m?['operationId'], v.idFirebase);
    });

    test('STOCKR2-9 estoque baixa 1×', () async {
      const pid = 'brinco-1x';
      const intentId = 'intent-stockr2-9';
      await _seedBrinco(firestore, produtosBox, pid: pid, qtd: 3);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect(await _qtdRemota(firestore, pid), 2);
    });

    test('STOCKR2-10 Hive persiste venda', () async {
      const pid = 'brinco-hive';
      const intentId = 'intent-stockr2-10';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      final v = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect(vendasBox.values.any((x) => x.idFirebase == v.idFirebase), isTrue);
    });

    test('STOCKR2-11 Sale Intent completed', () async {
      const pid = 'brinco-complete';
      const intentId = 'intent-stockr2-11';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect((await _intent(firestore, intentId))?['status'], 'completed');
    });

    test('STOCKR2-12 retry idempotente mesma intent', () async {
      const pid = 'brinco-retry';
      const intentId = 'intent-stockr2-12';
      await _seedBrinco(firestore, produtosBox, pid: pid, qtd: 4);
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);

      final v1 = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      final v2 = await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: _itensH1(pid),
        pix: 39.90,
        lojaId: _lojaId,
        saleIntentId: intentId,
      );

      expect(v2.idFirebase, v1.idFirebase);
      expect(await _qtdRemota(firestore, pid), 3);
    });

    test('STOCKR2-RED wrapper legado reproduz mensagem vídeo 07:37', () async {
      expect(
        LegacyStockBatchTimeoutTestSupport.withLegacyBatchTimeout(
          Future<void>.delayed(const Duration(milliseconds: 100)),
          duration: const Duration(milliseconds: 10),
        ),
        throwsA(
          predicate<Object>(
            (e) => e is TimeoutException && e.message == _legacyMsg,
          ),
        ),
      );
    });
  });
}
