// H1STUCK-1…15 — silent stuck pós-86a7bba (UI + recovery marker/intent).

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/loja_ativa_resolver.dart';
import 'package:master_palm/core/nova_venda_pos_save_ui_policy.dart';
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
    'variacoes': {
      '7mm': {'cristal': qtd},
    },
    'estoquePorTamanho': {'7mm': qtd},
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

Future<Venda> _registrarH1({
  required FakeFirebaseFirestore fs,
  required Box<Produto> produtosBox,
  required Box<Cliente> clientesBox,
  required Box<Venda> vendasBox,
  required Cliente c,
  required String pid,
  required String intentId,
}) {
  return VendasService.registrarVendaMulti(
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
    hiveDir = await Directory.systemTemp.createTemp('hive_h1stuck_');
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
    produtosBox = await Hive.openBox<Produto>('p_h1stuck_$s');
    clientesBox = await Hive.openBox<Cliente>('c_h1stuck_$s');
    vendasBox = await Hive.openBox<Venda>('v_h1stuck_$s');
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

  group('H1STUCK — UI policy', () {
    test('H1STUCK-11 legacy: falha com mounted=false era silenciosa', () {
      expect(
        legacyNovaVendaPosSaveUiIsSilent(
          ok: false,
          mensagemErro: 'Falha de estoque',
          mounted: false,
        ),
        isTrue,
      );
    });

    test('H1STUCK-12 legacy: falha com msg vazia era silenciosa', () {
      expect(
        legacyNovaVendaPosSaveUiIsSilent(
          ok: false,
          mensagemErro: '',
          mounted: true,
        ),
        isTrue,
      );
    });

    test('H1STUCK-13 pós-fix: falha nunca é silenciosa', () {
      final d1 = decideNovaVendaPosSaveUi(
        ok: false,
        mensagemErro: 'Erro',
        mounted: true,
      );
      expect(d1.action, NovaVendaPosSaveUiAction.showErrorDialog);

      final d2 = decideNovaVendaPosSaveUi(
        ok: false,
        mensagemErro: 'Erro',
        mounted: false,
      );
      expect(d2.action, NovaVendaPosSaveUiAction.notifyParentError);
      expect(d2.errorMessage, isNotEmpty);
    });

    test('H1STUCK-13 pós-fix: falha sem mensagem usa fallback', () {
      final d = decideNovaVendaPosSaveUi(
        ok: false,
        mensagemErro: null,
        mounted: true,
      );
      expect(d.action, NovaVendaPosSaveUiAction.showErrorDialog);
      expect(d.errorMessage, novaVendaPosSaveFallbackError);
    });
  });

  group('H1STUCK — recovery fluxo H1', () {
    Future<Cliente> _cliente() async {
      final c = Cliente(
        nome: 'Cli',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);
      return c;
    }

    test('H1STUCK-1 baseline conclui', () async {
      const pid = 'brinco-1';
      const intentId = 'intent-h1stuck-1';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final c = await _cliente();
      final v = await _registrarH1(
        fs: firestore,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        c: c,
        pid: pid,
        intentId: intentId,
      );
      expect(v.idFirebase, isNotEmpty);
      expect(vendasBox.values.any((x) => x.idFirebase == v.idFirebase), isTrue);
    });

    test('H1STUCK-4 marker baixaAplicada=true sem venda ainda conclui', () async {
      const pid = 'brinco-4';
      const intentId = 'intent-h1stuck-4';
      const opId = 'op-marker-orphan';
      await _seedBrinco(firestore, produtosBox, pid: pid);
      final txItems = [
        {
          'productId': pid,
          'quantidade': 1,
          'tamanho': '7mm',
          'cor': 'cristal',
        },
      ];
      final hash =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(txItems);
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: txItems,
        operationId: opId,
      );
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('sale_intents')
          .doc(intentId)
          .set({
        'protocolVersion': 1,
        'saleIntentId': intentId,
        'lojaId': _lojaId,
        'origin': SaleIntentOrigins.pdvManual,
        'operationId': opId,
        'status': SaleIntentStatus.reserved.wireValue,
        'stockEffectHash': hash,
      });
      final c = await _cliente();
      final v = await _registrarH1(
        fs: firestore,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        c: c,
        pid: pid,
        intentId: intentId,
      );
      expect(v.idFirebase, opId);
      expect(vendasBox.values.any((x) => x.idFirebase == opId), isTrue);
    });

    test('H1STUCK-7 outcome alreadyApplied persiste venda', () async {
      const pid = 'brinco-7';
      const intentId = 'intent-h1stuck-7';
      const opId = 'op-pre-applied';
      await _seedBrinco(firestore, produtosBox, pid: pid, qtd: 3);
      final txItems = [
        {
          'productId': pid,
          'quantidade': 1,
          'tamanho': '7mm',
          'cor': 'cristal',
        },
      ];
      final hash =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(txItems);
      final op = await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: txItems,
        operationId: opId,
      );
      expect(op.status, EstoqueBaixaOperationStatus.applied);

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('sale_intents')
          .doc(intentId)
          .set({
        'protocolVersion': 1,
        'saleIntentId': intentId,
        'lojaId': _lojaId,
        'origin': SaleIntentOrigins.pdvManual,
        'operationId': opId,
        'status': SaleIntentStatus.reserved.wireValue,
        'stockEffectHash': hash,
      });
      final c = await _cliente();
      final v = await _registrarH1(
        fs: firestore,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        c: c,
        pid: pid,
        intentId: intentId,
      );
      expect(v.idFirebase, opId);
      expect(vendasBox.length, greaterThan(0));
    });

    test('H1STUCK-14 retry após marker órfão converge 1 venda', () async {
      const pid = 'brinco-14';
      const intentId = 'intent-h1stuck-14';
      const opId = 'op-retry-14';
      await _seedBrinco(firestore, produtosBox, pid: pid, qtd: 4);
      final txItems = [
        {
          'productId': pid,
          'quantidade': 1,
          'tamanho': '7mm',
          'cor': 'cristal',
        },
      ];
      final hash =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(txItems);
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: txItems,
        operationId: opId,
      );
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection('sale_intents')
          .doc(intentId)
          .set({
        'protocolVersion': 1,
        'saleIntentId': intentId,
        'lojaId': _lojaId,
        'origin': SaleIntentOrigins.pdvManual,
        'operationId': opId,
        'status': SaleIntentStatus.stockApplied.wireValue,
        'stockEffectHash': hash,
      });
      final c = await _cliente();
      final v = await _registrarH1(
        fs: firestore,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        c: c,
        pid: pid,
        intentId: intentId,
      );
      expect(v.idFirebase, opId);
      expect(vendasBox.values.where((x) => x.idFirebase == opId).length, 1);
    });

    test('H1STUCK-15 dois cliques mesma intent não duplicam venda', () async {
      const pid = 'brinco-15';
      const intentId = 'intent-h1stuck-15';
      await _seedBrinco(firestore, produtosBox, pid: pid, qtd: 5);
      final c = await _cliente();
      final f1 = _registrarH1(
        fs: firestore,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        c: c,
        pid: pid,
        intentId: intentId,
      );
      final f2 = _registrarH1(
        fs: firestore,
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        c: c,
        pid: pid,
        intentId: intentId,
      );
      final r1 = await f1;
      final r2 = await f2;
      expect(r1.idFirebase, r2.idFirebase);
      expect(
        vendasBox.values.where((x) => x.idFirebase == r1.idFirebase).length,
        1,
      );
    });
  });
}
