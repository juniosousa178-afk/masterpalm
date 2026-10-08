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
import 'package:master_palm/services/catalog_publish_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/catalogo_web_apos_estoque_service.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/sale_intent_service.dart';
import 'package:master_palm/services/venda_operation_journal_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-post-ui-cat';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late Directory hiveDir;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;
  late Box<Map> journalBox;
  late List<String> phases;
  late int editorialAtUi;
  late int publishAtUi;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_post_ui_cat_');
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
    phases = <String>[];
    editorialAtUi = -1;
    publishAtUi = -1;
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    VendasService.debugOperacoesEmAndamentoClearForTests();
    CatalogoWebAposEstoqueService.debugClearHooks();
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    SaleIntentService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
    CatalogoSyncService.debugFirestoreOverride = firestore;
    CatalogPublishService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_pui_$s');
    clientesBox = await Hive.openBox<Cliente>('c_pui_$s');
    vendasBox = await Hive.openBox<Venda>('v_pui_$s');
    journalBox = await Hive.openBox<Map>(
      HiveBoxNames.vendaOperationJournal(_lojaId),
    );
    await journalBox.clear();
    VendaOperationJournalService.debugBoxOverride = journalBox;

    CatalogoWebAposEstoqueService.debugBeforeEditorial = (id) async {
      phases.add('editorial:$id');
    };
    CatalogoWebAposEstoqueService.debugBeforePublish = (id) async {
      phases.add('publish:$id');
    };
  });

  tearDown(() async {
    CatalogoWebAposEstoqueService.debugClearHooks();
    VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete = null;
    SaleIntentService.debugClearOverride();
    VendaOperationJournalService.debugClearOverride();
    LojaAtivaResolver.debugResolveOverride = null;
    EstoqueTransactionService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    CatalogPublishService.debugFirestoreOverride = null;
    await produtosBox.close();
    await clientesBox.close();
    await vendasBox.close();
    if (Hive.isBoxOpen(HiveBoxNames.vendaOperationJournal(_lojaId))) {
      await journalBox.close();
    }
  });

  Future<void> seedProduto({
    required String pid,
    required int qtd,
  }) async {
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({
      'nome': pid,
      'quantidade': qtd,
      'lojaId': _lojaId,
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = pid
        ..idFirebase = pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 10
        ..publicadoNoCatalogo = true,
    );
  }

  Future<Cliente> seedCliente() async {
    final c = Cliente(
      nome: 'Cliente PDV',
      telefone: '11999999999',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<int> qtdRemota(String pid) async {
    final snap = await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .get();
    return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
  }

  Future<int?> qtdColecao(String colecao, String pid) async {
    final snap = await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(colecao)
        .doc(pid)
        .get();
    if (!snap.exists) return null;
    return (snap.data()?['quantidade'] as num?)?.toInt();
  }

  Future<Venda> vender({
    required Cliente cliente,
    required List<VendaItem> itens,
    required String intentId,
    void Function()? onUi,
    Future<void> Function()? beforeUi,
    void Function(String message)? onSyncError,
  }) {
    final total = itens.fold<double>(
      0,
      (s, it) => s + it.precoUnitario * it.quantidade,
    );
    VendasService.debugAfterHiveSalePersistedBeforeSaleIntentComplete =
        beforeUi;
    return VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: cliente.nome,
      clienteExistente: cliente,
      itens: itens,
      dinheiro: total,
      lojaId: _lojaId,
      saleIntentId: intentId,
      onLocalPersistUiReady: () {
        editorialAtUi = phases.where((p) => p.startsWith('editorial:')).length;
        publishAtUi = phases.where((p) => p.startsWith('publish:')).length;
        onUi?.call();
      },
      onSyncError: onSyncError,
    );
  }

  List<VendaItem> itensDe(Map<String, int> qtdPorProduto) {
    return [
      for (final e in qtdPorProduto.entries)
        VendaItem(
          produtoNome: e.key,
          quantidade: e.value,
          precoUnitario: 10,
          productId: e.key,
        ),
    ];
  }

  test('quatro produtos: catálogo só depois da UI e estoque canônico por item', () async {
    const iniciais = {
      'p1': 5,
      'p2': 8,
      'p3': 3,
      'p4': 10,
    };
    for (final e in iniciais.entries) {
      await seedProduto(pid: e.key, qtd: e.value);
    }
    final cliente = await seedCliente();
    var journalVazioNaUi = false;
    var vendasNaUi = -1;
    String? intentNaUi;
    final qtdNaUi = <String, int>{};

    final sw = Stopwatch()..start();
    var uiMs = 0;
    final venda = await vender(
      cliente: cliente,
      itens: itensDe({for (final id in iniciais.keys) id: 1}),
      intentId: 'intent-4',
      onUi: () {
        uiMs = sw.elapsedMilliseconds;
      },
      beforeUi: () async {
        expect(phases, isEmpty);
        journalVazioNaUi = journalBox.isEmpty;
        vendasNaUi = vendasBox.length;
        final intent = await firestore
            .collection('lojas')
            .doc(_lojaId)
            .collection('sale_intents')
            .doc('intent-4')
            .get();
        intentNaUi = intent.data()?['status'] as String?;
        for (final id in iniciais.keys) {
          qtdNaUi[id] = await qtdRemota(id);
        }
      },
    );
    sw.stop();

    expect(editorialAtUi, 0);
    expect(publishAtUi, 0);
    expect(journalVazioNaUi, isTrue);
    expect(vendasNaUi, 1);
    expect(intentNaUi, 'sale_persisted');
    expect(venda.idFirebase, isNotEmpty);
    expect(vendasBox.length, 1);

    final editoriais = phases.where((p) => p.startsWith('editorial:')).toList();
    final publishes = phases.where((p) => p.startsWith('publish:')).toList();
    expect(editoriais, hasLength(4));
    expect(publishes, hasLength(4));
    for (final id in iniciais.keys) {
      final iEd = phases.indexOf('editorial:$id');
      final iPub = phases.indexOf('publish:$id');
      expect(iEd, greaterThanOrEqualTo(0));
      expect(iPub, greaterThan(iEd));
      final proximoEditorial = phases.indexWhere(
        (p) => p.startsWith('editorial:') && p != 'editorial:$id',
        iEd + 1,
      );
      if (proximoEditorial != -1) {
        expect(iPub, lessThan(proximoEditorial));
      }
      expect(qtdNaUi[id], iniciais[id]! - 1);
      expect(await qtdRemota(id), iniciais[id]! - 1);
      expect(await qtdColecao('draft_produtos', id), iniciais[id]! - 1);
      expect(await qtdColecao('produtos', id), iniciais[id]! - 1);
    }
    // ignore: avoid_print
    print('[SALE-UI-READY] items=4 ms=$uiMs');
  });

  test('venda de 5 para 4 projeta o estoque canônico depois da UI', () async {
    await seedProduto(pid: 'anel', qtd: 5);
    final cliente = await seedCliente();
    var qtdNaUi = -1;
    await vender(
      cliente: cliente,
      itens: itensDe({'anel': 1}),
      intentId: 'intent-anel',
      beforeUi: () async {
        qtdNaUi = await qtdRemota('anel');
      },
    );
    expect(editorialAtUi, 0);
    expect(qtdNaUi, 4);
    expect(await qtdRemota('anel'), 4);
    expect(await qtdColecao('draft_produtos', 'anel'), 4);
    expect(await qtdColecao('produtos', 'anel'), 4);
    expect(phases.where((p) => p.startsWith('editorial:')), ['editorial:anel']);
    expect(phases.where((p) => p.startsWith('publish:')), ['publish:anel']);
  });

  test('falha de catalogPublishOne não reverte venda nem repete baixa', () async {
    await seedProduto(pid: 'brinco', qtd: 5);
    final cliente = await seedCliente();
    final syncMsgs = <String>[];
    CatalogoWebAposEstoqueService.debugBeforePublish = (id) async {
      phases.add('publish:$id');
      throw StateError('publish-forcado');
    };
    final venda = await vender(
      cliente: cliente,
      itens: itensDe({'brinco': 1}),
      intentId: 'intent-falha',
      onSyncError: syncMsgs.add,
    );
    expect(editorialAtUi, 0);
    expect(venda.idFirebase, isNotEmpty);
    expect(vendasBox.length, 1);
    expect(journalBox.isEmpty, isTrue);
    expect(await qtdRemota('brinco'), 4);
    expect(phases.where((p) => p.startsWith('editorial:')), hasLength(1));
    expect(phases.where((p) => p.startsWith('publish:')), hasLength(1));
    expect(await qtdColecao('produtos', 'brinco'), isNull);
    expect(
      syncMsgs.where((m) => m.toLowerCase().contains('não foi salva')),
      isEmpty,
    );
    final markers = await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection('estoque_baixa_pagamento')
        .get();
    expect(markers.docs, hasLength(1));
  });

  test('publicação lenta de 3 produtos não entra no tempo até a UI', () async {
    for (final id in ['a', 'b', 'c']) {
      await seedProduto(pid: id, qtd: 5);
    }
    final cliente = await seedCliente();
    CatalogoWebAposEstoqueService.debugBeforePublish = (id) async {
      phases.add('publish:$id');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    };
    final uiSw = Stopwatch()..start();
    var uiMs = 0;
    final totalSw = Stopwatch()..start();
    await vender(
      cliente: cliente,
      itens: itensDe({'a': 1, 'b': 1, 'c': 1}),
      intentId: 'intent-lento',
      onUi: () {
        uiMs = uiSw.elapsedMilliseconds;
      },
    );
    totalSw.stop();
    expect(editorialAtUi, 0);
    expect(publishAtUi, 0);
    expect(uiMs, lessThan(totalSw.elapsedMilliseconds - 3000));
    expect(totalSw.elapsedMilliseconds, greaterThanOrEqualTo(4500));
    expect(await qtdRemota('a'), 4);
    expect(await qtdRemota('b'), 4);
    expect(await qtdRemota('c'), 4);
    // ignore: avoid_print
    print(
      '[SALE-UI-READY] slow3 uiMs=$uiMs totalMs=${totalSw.elapsedMilliseconds}',
    );
  });

  test('tempo até a UI com 1, 2 e 10 itens não espera o catálogo', () async {
    Future<int> medir(int n) async {
      phases.clear();
      final ids = [for (var i = 0; i < n; i++) 'n$n-$i'];
      for (final id in ids) {
        await seedProduto(pid: id, qtd: 5);
      }
      final cliente = await seedCliente();
      var uiMs = 0;
      final sw = Stopwatch()..start();
      await vender(
        cliente: cliente,
        itens: itensDe({for (final id in ids) id: 1}),
        intentId: 'intent-n$n-${DateTime.now().microsecondsSinceEpoch}',
        onUi: () {
          uiMs = sw.elapsedMilliseconds;
        },
      );
      expect(editorialAtUi, 0);
      expect(publishAtUi, 0);
      expect(phases.where((p) => p.startsWith('publish:')), hasLength(n));
      return uiMs;
    }

    final ms1 = await medir(1);
    final ms2 = await medir(2);
    final ms10 = await medir(10);
    // ignore: avoid_print
    print('[SALE-UI-READY] items=1 ms=$ms1');
    // ignore: avoid_print
    print('[SALE-UI-READY] items=2 ms=$ms2');
    // ignore: avoid_print
    print('[SALE-UI-READY] items=10 ms=$ms10');
    expect(ms1, lessThan(3000));
    expect(ms2, lessThan(3000));
    expect(ms10, lessThan(3000));
  });
}
