// P0 Nathy: piso de combo pós-estorno abortava a exclusão da venda com
// StateError('Estorno exige a operação original da venda.') depois de o
// restore autoritativo já ter sido aplicado.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/delete_forensic_trace.dart';
import 'package:master_palm/core/hive_box_names.dart';
import 'package:master_palm/core/produto_untracked_stock_conflict.dart';
import 'package:master_palm/core/venda_exclusao_tombstone.dart';
import 'package:master_palm/models/cliente.dart';
import 'package:master_palm/models/conta_receber.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/services/catalog_publish_service.dart';
import 'package:master_palm/services/catalogo_sync_service.dart';
import 'package:master_palm/services/combo_kit_stock_service.dart';
import 'package:master_palm/services/conta_receber_firestore_service.dart';
import 'package:master_palm/services/conta_receber_service.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:master_palm/services/soft_delete_service.dart';
import 'package:master_palm/services/stock_catalog_backend_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _store = 'nathy-pratas-e-folheados';
const _saleOp = '5871caa3-7ef3-4733-b12a-7e6745d1ee0c';
const _limpa = 'nathy-pratas-e-folheados-limpa-prata';
const _anel = 'nathy-pratas-e-folheados-anel-elos-cora-ozinho';
const _saleA = '0000000a-0000-4000-8000-00000000000a';
const _saleB = '0000000b-0000-4000-8000-00000000000b';
const _saleC = '0000000c-0000-4000-8000-00000000000c';
const _saleD = '0000000d-0000-4000-8000-00000000000d';
const _saleE = '0000000e-0000-4000-8000-00000000000e';
const _saleR = '00000001-0000-4000-8000-000000000001';

String _restoreIdFor(String source) =>
    'restore_${sha256.convert(utf8.encode(source))}';

/// Emula o contrato de `stockCatalogCommand` kind=restore
/// (functions/src/stockCatalogCommands.js + stockCatalogCombo.js).
class _FakeRestoreBackend {
  _FakeRestoreBackend(this.fs);

  final FakeFirebaseFirestore fs;
  final Map<String, Map<String, dynamic>> ops = {};

  /// comboId → receita; só combos com dependência registrada entram na TX.
  final Map<String, List<({String productId, int qty})>> linkedCombos = {};

  int restoreCalls = 0;
  int restoreApplied = 0;
  int restoreAlreadyApplied = 0;
  int restoreWithoutSource = 0;
  final List<String> otherCalls = [];
  bool failRestore = false;

  DocumentReference<Map<String, dynamic>> _ref(String id) => fs
      .collection('lojas')
      .doc(_store)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(id);

  Future<Map<String, dynamic>> _data(String id) async =>
      Map<String, dynamic>.from((await _ref(id).get()).data() ?? {});

  void seedAppliedSale(
    String opId,
    List<Map<String, dynamic>> items, {
    String? restoredBy,
  }) {
    ops[opId] = {
      'kind': 'sale',
      'status': 'applied',
      'legacyCompat': true,
      'items': items,
      if (restoredBy != null) 'restoredBy': restoredBy,
    };
    if (restoredBy != null) {
      ops[restoredBy] = {
        'kind': 'restore',
        'status': 'applied',
        'sourceOperationId': opId,
      };
    }
  }

  Future<Map<String, dynamic>> transport(
    String name,
    Map<String, dynamic> data,
  ) async {
    if (name != 'stockCatalogCommand' || data['kind'] != 'restore') {
      otherCalls.add('$name:${data['kind']}');
      return {'ok': true, 'products': <Map<String, dynamic>>[]};
    }
    restoreCalls++;
    final source = (data['sourceOperationId'] as String?)?.trim() ?? '';
    if (source.isEmpty) {
      restoreWithoutSource++;
      throw Exception('[firebase_functions/invalid-argument] source required');
    }
    if (failRestore) {
      throw Exception('[firebase_functions/unavailable] forced restore failure');
    }
    final opId = data['operationId'] as String;
    expect(opId, _restoreIdFor(source));
    final sale = ops[source];
    if (sale == null || sale['kind'] != 'sale' || sale['status'] != 'applied') {
      throw Exception(
        '[firebase_functions/failed-precondition] Applied sale required',
      );
    }
    final items = List<Map<String, dynamic>>.from(sale['items'] as List);
    if (ops.containsKey(opId)) {
      restoreAlreadyApplied++;
      return {
        'alreadyApplied': true,
        'operationId': opId,
        'products': await _rows(_touchedIds(items)),
      };
    }
    final restoredBy = sale['restoredBy'];
    if (restoredBy != null && restoredBy != opId) {
      throw Exception('[firebase_functions/already-exists] Sale already restored');
    }

    for (final it in items) {
      final pid = it['productId'] as String;
      final d = await _data(pid);
      final q = (it['quantity'] as num).toInt();
      final size = (it['size'] ?? '').toString();
      final color = (it['color'] ?? '').toString();
      if (size.isNotEmpty) {
        final grade = Map<String, dynamic>.from(d['variacoes'] as Map? ?? {});
        final cell = Map<String, dynamic>.from(grade[size] as Map? ?? {});
        cell[color] = ((cell[color] as num?)?.toInt() ?? 0) + q;
        grade[size] = cell;
        d['variacoes'] = grade;
        final porTam =
            Map<String, dynamic>.from(d['estoquePorTamanho'] as Map? ?? {});
        porTam[size] = ((porTam[size] as num?)?.toInt() ?? 0) + q;
        d['estoquePorTamanho'] = porTam;
      }
      d['quantidade'] = ((d['quantidade'] as num?)?.toInt() ?? 0) + q;
      d['stockRevision'] = ((d['stockRevision'] as num?)?.toInt() ?? 0) + 1;
      d['stockOperationId'] = opId;
      await _ref(pid).set(d);
    }
    final touched = _touchedIds(items);
    for (final comboId in touched.where(linkedCombos.containsKey)) {
      int? cap;
      for (final c in linkedCombos[comboId]!) {
        final comp = await _data(c.productId);
        final k = ((comp['quantidade'] as num?)?.toInt() ?? 0) ~/ c.qty;
        cap = cap == null ? k : (k < cap ? k : cap);
      }
      final d = await _data(comboId);
      d['quantidade'] = cap ?? 0;
      d['stockRevision'] = ((d['stockRevision'] as num?)?.toInt() ?? 0) + 1;
      d['stockOperationId'] = opId;
      await _ref(comboId).set(d);
    }
    sale['restoredBy'] = opId;
    ops[opId] = {
      'kind': 'restore',
      'status': 'applied',
      'sourceOperationId': source,
    };
    restoreApplied++;
    return {
      'alreadyApplied': false,
      'operationId': opId,
      'products': await _rows(touched),
    };
  }

  Set<String> _touchedIds(List<Map<String, dynamic>> items) {
    final ids = {for (final it in items) it['productId'] as String};
    for (final e in linkedCombos.entries) {
      if (e.value.any((c) => ids.contains(c.productId))) ids.add(e.key);
    }
    return ids;
  }

  Future<List<Map<String, dynamic>>> _rows(Set<String> ids) async {
    final out = <Map<String, dynamic>>[];
    for (final id in ids) {
      final d = await _data(id);
      out.add({
        'productId': id,
        'nome': d['nome'],
        'slug': d['slug'] ?? id,
        'stockKind': d['stockKind'] ?? 'simple',
        'quantidade': d['quantidade'],
        'stockRevision': d['stockRevision'],
        'stockOperationId': d['stockOperationId'],
        'variacoes': d['variacoes'] ?? <String, dynamic>{},
        'estoquePorTamanho': d['estoquePorTamanho'] ?? <String, dynamic>{},
        'estoquePorCor': <String, int>{},
      });
    }
    return out;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late FakeFirebaseFirestore fs;
  late _FakeRestoreBackend backend;
  late Box<Produto> produtosBox;
  late Box<Venda> vendasBox;
  late Box<Cliente> clientesBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_combo_piso_pos_');
    Hive.init(hiveDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
    if (!Hive.isAdapterRegistered(29)) {
      Hive.registerAdapter(ContaReceberAdapter());
    }
    DeleteForensicTraceStore.disableHive = true;
    UntrackedStockConflictStore.disableHive = true;
    produtosBox = await Hive.openBox<Produto>(HiveBoxNames.produtos(_store));
    vendasBox = await Hive.openBox<Venda>(HiveBoxNames.vendas(_store));
    clientesBox = await Hive.openBox<Cliente>(HiveBoxNames.clientes(_store));
  });

  tearDownAll(() async {
    DeleteForensicTraceStore.disableHive = false;
    UntrackedStockConflictStore.disableHive = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    VendaExclusaoTombstone.resetForTests();
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    fs = FakeFirebaseFirestore();
    backend = _FakeRestoreBackend(fs);
    EstoqueTransactionService.debugClearOverrides();
    StockCatalogBackendService.debugTransport = backend.transport;
    ProdutosFirestoreService.debugFirestoreOverride = fs;
    ContaReceberFirestoreService.debugFirestoreOverride = fs;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = fs;
    CatalogoSyncService.debugFirestoreOverride = fs;
    CatalogPublishService.debugFirestoreOverride = fs;
    await produtosBox.clear();
    await vendasBox.clear();
    await clientesBox.clear();
    final crBox = await ContaReceberService.openBoxLoja(_store);
    await crBox.clear();
  });

  tearDown(() {
    EstoqueTransactionService.debugClearOverrides();
    StockCatalogBackendService.debugTransport = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    ContaReceberFirestoreService.debugFirestoreOverride = null;
    ProdutoExclusaoTombstoneService.debugFirestoreOverride = null;
    CatalogoSyncService.debugFirestoreOverride = null;
    CatalogPublishService.debugFirestoreOverride = null;
  });

  CollectionReference<Map<String, dynamic>> col(String name) =>
      fs.collection('lojas').doc(_store).collection(name);

  Future<Map<String, dynamic>?> remoto(String colName, String id) async {
    final snap = await fs
        .collection('lojas')
        .doc(_store)
        .collection(colName)
        .doc(id)
        .get();
    return snap.data();
  }

  Future<int?> qtdCanonica(String id) async =>
      ((await remoto(FSPaths.estoqueProdutosCol, id))?['quantidade'] as num?)
          ?.toInt();

  Produto? hive(String id) {
    for (final p in produtosBox.values) {
      if (p.idFirebase == id) return p;
    }
    return null;
  }

  Future<void> seedSimples(
    String id, {
    required int qtd,
    int rev = 1,
    String? op,
    int? hiveQtd,
  }) async {
    await col(FSPaths.estoqueProdutosCol).doc(id).set({
      'nome': id,
      'slug': id,
      'lojaId': _store,
      'stockKind': 'simple',
      'quantidade': qtd,
      'stockRevision': rev,
      if (op != null) 'stockOperationId': op,
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = id
        ..slug = id
        ..idFirebase = id
        ..lojaId = _store
        ..quantidade = hiveQtd ?? qtd
        ..stockRevision = rev
        ..precoFinal = 30
        ..publicadoNoCatalogo = true,
    );
  }

  Future<void> seedCombo(
    String id, {
    required List<String> componentes,
    required int qtdCanonica,
    int? hiveQtd,
  }) async {
    await col(FSPaths.estoqueProdutosCol).doc(id).set({
      'nome': id,
      'slug': id,
      'lojaId': _store,
      'stockKind': 'simple',
      'tipoProduto': 'combo',
      'quantidade': qtdCanonica,
      'stockRevision': 1,
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = id
        ..slug = id
        ..idFirebase = id
        ..lojaId = _store
        ..tipoProduto = 'combo'
        ..itensCombo = [
          for (final c in componentes) {'id': c, 'nome': c, 'quantidade': 1},
        ]
        ..quantidade = hiveQtd ?? qtdCanonica
        ..stockRevision = 1
        ..precoFinal = 80
        ..publicadoNoCatalogo = true,
    );
  }

  /// Estado real da Nathy após o restore de 2026-10-08T01:11:32.538Z.
  Future<void> seedNathyPosRestore() async {
    final restoreId = _restoreIdFor(_saleOp);
    await seedSimples(_limpa, qtd: 9, rev: 5, op: restoreId);
    final grade = {
      '12': {'sem-cor': 4},
      '14': {'sem-cor': 6},
      '16': {'sem-cor': 10},
    };
    await col(FSPaths.estoqueProdutosCol).doc(_anel).set({
      'nome': 'Anel Elos Coraçãozinho',
      'slug': _anel,
      'lojaId': _store,
      'stockKind': 'variation',
      'quantidade': 20,
      'stockRevision': 17,
      'stockOperationId': restoreId,
      'variacoes': grade,
      'estoquePorTamanho': {'12': 4, '14': 6, '16': 10},
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Anel Elos Coraçãozinho'
        ..slug = _anel
        ..idFirebase = _anel
        ..lojaId = _store
        ..variacoes = {
          for (final e in grade.entries)
            e.key: Map<String, dynamic>.from(e.value),
        }
        ..estoquePorTamanho = {'12': 4, '14': 6, '16': 10}
        ..quantidade = 20
        ..stockRevision = 17
        ..precoFinal = 34.9
        ..publicadoNoCatalogo = true,
    );
    backend.seedAppliedSale(
      _saleOp,
      [
        {'productId': _limpa, 'quantity': 1},
        {'productId': _anel, 'quantity': 1, 'size': '12', 'color': 'sem-cor'},
      ],
      restoredBy: restoreId,
    );
  }

  /// 15 combos legados: 6 abaixo do piso montável, 1 sem componente, 8 no teto.
  Future<void> seedCombosLegadosNathy() async {
    await seedSimples('nathy-comp-a', qtd: 30);
    for (var i = 1; i <= 6; i++) {
      await seedCombo('nathy-combo-abaixo-$i',
          componentes: ['nathy-comp-a'], qtdCanonica: 2);
    }
    await seedCombo('nathy-combo-sem-comp',
        componentes: ['nathy-comp-inexistente'], qtdCanonica: 0);
    for (var i = 1; i <= 8; i++) {
      await seedCombo('nathy-combo-teto-$i',
          componentes: ['nathy-comp-a'], qtdCanonica: 30);
    }
  }

  Future<Venda> seedVenda({
    required String idFirebase,
    required List<VendaItem> itens,
    String formas = 'PIX',
    double total = 64.9,
  }) async {
    await clientesBox.add(
      Cliente(
        nome: 'Cliente',
        telefone: '11999999999',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _store,
      ),
    );
    final venda = Venda(
      clienteNome: 'Cliente',
      produtosDescricao: itens.map((e) => e.produtoNome).join(', '),
      quantidade: itens.fold<int>(0, (a, e) => a + e.quantidade),
      preco: total,
      total: total,
      formasPagamento: formas,
      data: DateTime(2026, 10, 8),
      vendedor: 'Loja',
      observacao: '',
      lojaId: _store,
      itens: itens,
    );
    venda.idFirebase = idFirebase;
    venda.stockOperationId = idFirebase;
    await vendasBox.add(venda);
    return venda;
  }

  Future<Venda> seedVendaNathy() => seedVenda(
        idFirebase: _saleOp,
        itens: [
          VendaItem(
            produtoNome: 'Limpa Prata',
            quantidade: 1,
            precoUnitario: 30,
            productId: _limpa,
            lojaId: _store,
          ),
          VendaItem(
            produtoNome: 'Anel Elos Coraçãozinho',
            quantidade: 1,
            precoUnitario: 34.9,
            tamanho: '12',
            cor: 'sem-cor',
            productId: _anel,
            lojaId: _store,
          ),
        ],
      );

  Future<void> excluir(Venda venda) => SoftDeleteService.scheduleVendaDelete(
        venda: venda,
        vendasBox: vendasBox,
        clientesBox: clientesBox,
        lojaId: _store,
      );

  Future<int> lixeiraCom(String idFirebase) async {
    final trash = await Hive.openBox<Venda>('trash_vendas');
    return trash.values.where((v) => v.idFirebase == idFirebase).length;
  }

  Future<Map<String, int?>> snapshotCombos(Iterable<String> ids) async => {
        for (final id in ids) id: await qtdCanonica(id),
      };

  group('Reprodução Nathy — restore já aplicado + 15 combos legados', () {
    test(
        'retry da exclusão: sem StateError, sem 2º restore, exclusão conclui 1x',
        () async {
      await seedNathyPosRestore();
      await seedCombosLegadosNathy();
      final venda = await seedVendaNathy();

      final combos = produtosBox.values.where((p) => p.ehCombo).toList();
      expect(combos, hasLength(15));
      final abaixoDoPiso = combos
          .where((c) =>
              ComboKitStockService.maxKitsMontaveis(c, produtosBox, _store) >
              c.quantidade)
          .length;
      expect(abaixoDoPiso, 6, reason: 'fixture = 6 combos abaixo do piso K');

      final combosAntesRemoto = await snapshotCombos(
        combos.map((c) => c.idFirebase),
      );
      final combosAntesHive = {
        for (final c in combos) c.idFirebase: c.quantidade,
      };

      await excluir(venda);

      // SECOND_RESTORE_APPLIED_COUNT=0 / EXTRA_RESTORE_QTY=0 e 0
      expect(backend.restoreCalls, 1);
      expect(backend.restoreAlreadyApplied, 1);
      expect(backend.restoreApplied, 0);
      expect(backend.restoreWithoutSource, 0);
      expect(backend.otherCalls, isEmpty);
      expect(await qtdCanonica(_limpa), 9);
      expect(await qtdCanonica(_anel), 20);
      final anelRemoto = await remoto(FSPaths.estoqueProdutosCol, _anel);
      expect((anelRemoto!['variacoes'] as Map)['12'], {'sem-cor': 4});
      expect(anelRemoto['stockRevision'], 17);
      expect(
        (await remoto(FSPaths.estoqueProdutosCol, _limpa))!['stockRevision'],
        5,
      );
      expect(hive(_limpa)!.quantidade, 9);
      expect(hive(_anel)!.quantidade, 20);

      // UNRELATED_COMBOS_PROCESSED_DURING_DELETE=false
      expect(
        await snapshotCombos(combos.map((c) => c.idFirebase)),
        combosAntesRemoto,
      );
      expect(
        {for (final c in combos) c.idFirebase: c.quantidade},
        combosAntesHive,
      );

      // Exclusão concluída exatamente uma vez.
      expect(vendasBox.values.where((v) => v.idFirebase == _saleOp), isEmpty);
      expect(await lixeiraCom(_saleOp), 1);
      final tomb = await VendaExclusaoTombstone.idsParaLoja(_store);
      expect(tomb, contains(_saleOp));
    });

    test('mecanismo antigo (estorno sem source) ainda falha fechado no backend',
        () async {
      expect(
        () => EstoqueTransactionService.devolverEstoqueTransactionBatch(
          lojaId: _store,
          itens: [
            {'productId': 'nathy-combo-abaixo-1', 'quantidade': 28},
          ],
          vendaIdParaIdempotencia: null,
        ),
        throwsA(isA<StateError>()),
      );
      expect(backend.restoreCalls, 0);
    });

    test('retry após exclusão é idempotente (marcador local, sem novo restore)',
        () async {
      await seedNathyPosRestore();
      await seedCombosLegadosNathy();
      final venda = await seedVendaNathy();
      await excluir(venda);
      expect(backend.restoreCalls, 1);

      final trash = await Hive.openBox<Venda>('trash_vendas');
      final naLixeira = trash.values.lastWhere((v) => v.idFirebase == _saleOp);
      await VendasService.devolverEstoqueParaVendaRemovida(
        venda: naLixeira,
        produtosBox: produtosBox,
        lojaId: _store,
        explicitStockOperationId: _saleOp,
      );
      expect(backend.restoreCalls, 1, reason: 'DELETE_RETRY_IDEMPOTENT');
      expect(await qtdCanonica(_limpa), 9);
      expect(await qtdCanonica(_anel), 20);
    });

    test('catálogo: canônico == draft == live após a exclusão', () async {
      await seedNathyPosRestore();
      final venda = await seedVendaNathy();
      await excluir(venda);
      for (final id in [_limpa, _anel]) {
        final canon = await qtdCanonica(id);
        final draft =
            ((await remoto('draft_produtos', id))?['quantidade'] as num?)
                ?.toInt();
        final live =
            ((await remoto('produtos', id))?['quantidade'] as num?)?.toInt();
        expect(draft, canon, reason: 'draft $id');
        expect(live, canon, reason: 'live $id');
      }
    });
  });

  group('Combos — casos A–F', () {
    test('A NON_COMBO_SALE: estorno simples, nenhum combo tocado', () async {
      await seedSimples('prod-a', qtd: 4);
      backend.seedAppliedSale(_saleA, [
        {'productId': 'prod-a', 'quantity': 1},
      ]);
      final venda = await seedVenda(idFirebase: _saleA, itens: [
        VendaItem(
          produtoNome: 'prod-a',
          quantidade: 1,
          precoUnitario: 10,
          productId: 'prod-a',
          lojaId: _store,
        ),
      ]);
      await excluir(venda);
      expect(backend.restoreApplied, 1);
      expect(await qtdCanonica('prod-a'), 5);
      expect(hive('prod-a')!.quantidade, 5);
      expect(await lixeiraCom(_saleA), 1);
    });

    test('B COMBO_PRODUCT_SALE: combo recalculado pelo servidor na mesma TX',
        () async {
      await seedSimples('comp-x', qtd: 3);
      await seedSimples('comp-y', qtd: 5);
      await seedCombo('kit-b', componentes: ['comp-x', 'comp-y'], qtdCanonica: 3);
      backend.linkedCombos['kit-b'] = [
        (productId: 'comp-x', qty: 1),
        (productId: 'comp-y', qty: 1),
      ];
      backend.seedAppliedSale(_saleB, [
        {'productId': 'comp-x', 'quantity': 1},
        {'productId': 'comp-y', 'quantity': 1},
      ]);
      final venda = await seedVenda(idFirebase: _saleB, itens: [
        VendaItem(
          produtoNome: 'kit-b',
          quantidade: 1,
          precoUnitario: 80,
          productId: 'kit-b',
          lojaId: _store,
        ),
      ]);
      await excluir(venda);
      expect(backend.restoreApplied, 1);
      expect(await qtdCanonica('comp-x'), 4);
      expect(await qtdCanonica('comp-y'), 6);
      expect(await qtdCanonica('kit-b'), 4);
      expect(hive('kit-b')!.quantidade, 4);
      expect(await lixeiraCom(_saleB), 1);
    });

    test(
        'C COMBO_COMPONENT_SALE (NO_CONTROL): combo não creditado no servidor, '
        'Hive realinhado ao canônico', () async {
      await seedSimples('comp-c', qtd: 10);
      await seedCombo('kit-c', componentes: ['comp-c'], qtdCanonica: 2, hiveQtd: 7);
      backend.seedAppliedSale(_saleC, [
        {'productId': 'comp-c', 'quantity': 1},
      ]);
      final venda = await seedVenda(idFirebase: _saleC, itens: [
        VendaItem(
          produtoNome: 'comp-c',
          quantidade: 1,
          precoUnitario: 10,
          productId: 'comp-c',
          lojaId: _store,
        ),
      ]);
      await excluir(venda);
      expect(await qtdCanonica('comp-c'), 11);
      expect(await qtdCanonica('kit-c'), 2,
          reason: 'cliente nunca credita combo no estorno');
      expect(hive('kit-c')!.quantidade, 2);
      expect(await lixeiraCom(_saleC), 1);
    });

    test('D UNRELATED_COMBO_ISOLATION: combo sem vínculo fica intocado',
        () async {
      await seedSimples('comp-c', qtd: 10);
      await seedSimples('comp-outro', qtd: 50);
      await seedCombo('kit-d', componentes: ['comp-outro'], qtdCanonica: 1, hiveQtd: 9);
      backend.seedAppliedSale(_saleD, [
        {'productId': 'comp-c', 'quantity': 1},
      ]);
      final venda = await seedVenda(idFirebase: _saleD, itens: [
        VendaItem(
          produtoNome: 'comp-c',
          quantidade: 1,
          precoUnitario: 10,
          productId: 'comp-c',
          lojaId: _store,
        ),
      ]);
      await excluir(venda);
      expect(await qtdCanonica('kit-d'), 1);
      expect(hive('kit-d')!.quantidade, 9, reason: 'nem leitura nem escrita');
      expect(await lixeiraCom(_saleD), 1);
    });

    test('E MULTI_COMBO: todos os combos relacionados são reprojetados',
        () async {
      await seedSimples('comp-e', qtd: 10);
      await seedCombo('kit-e1', componentes: ['comp-e'], qtdCanonica: 2, hiveQtd: 7);
      await seedCombo('kit-e2', componentes: ['comp-e'], qtdCanonica: 3, hiveQtd: 8);
      backend.seedAppliedSale(_saleE, [
        {'productId': 'comp-e', 'quantity': 1},
      ]);
      final venda = await seedVenda(idFirebase: _saleE, itens: [
        VendaItem(
          produtoNome: 'comp-e',
          quantidade: 1,
          precoUnitario: 10,
          productId: 'comp-e',
          lojaId: _store,
        ),
      ]);
      await excluir(venda);
      expect(await qtdCanonica('kit-e1'), 2);
      expect(await qtdCanonica('kit-e2'), 3);
      expect(hive('kit-e1')!.quantidade, 2);
      expect(hive('kit-e2')!.quantidade, 3);
    });

    test('F LEGACY_NO_CONTROL: reprojeção é só leitura e idempotente',
        () async {
      await seedSimples('comp-f', qtd: 10);
      await seedCombo('kit-f', componentes: ['comp-f'], qtdCanonica: 4, hiveQtd: 1);
      final antes = await remoto(FSPaths.estoqueProdutosCol, 'kit-f');
      for (var i = 0; i < 2; i++) {
        final n = await ComboKitStockService.reprojetarCombosAposDevolucao(
          lojaId: _store,
          produtosBox: produtosBox,
          produtoIdsDevolvidos: {'comp-f'},
        );
        expect(n, 1);
        expect(hive('kit-f')!.quantidade, 4);
      }
      expect(await remoto(FSPaths.estoqueProdutosCol, 'kit-f'), antes,
          reason: 'COMBO_FLOOR_RETRY_IDEMPOTENT sem escrita remota');
      expect(backend.restoreCalls, 0);
    });
  });

  group('Erros por etapa', () {
    test('falha pós-estorno → mensagem neutra, sem texto técnico', () {
      final msg = EstoqueTransactionService.mensagemUsuarioFalhaDevolucaoEstoque(
        VendaExclusaoAposEstornoException(
          etapa: 'catalogo',
          cause: StateError('Estorno exige a operação original da venda.'),
        ),
      );
      expect(msg, startsWith(VendaExclusaoAposEstornoException.userMessage));
      expect(msg, contains('O estoque já foi devolvido com segurança'));
      expect(msg, isNot(contains('Não foi possível devolver o estoque')));
      expect(msg, isNot(contains('StateError')));
      expect(msg, isNot(contains('Estorno exige')));
      expect(msg, isNot(contains('firebase')));
    });

    test('falha real do restore → mensagem de estoque, venda preservada',
        () async {
      await seedSimples('prod-r', qtd: 4);
      backend.seedAppliedSale(_saleR, [
        {'productId': 'prod-r', 'quantity': 1},
      ]);
      final venda = await seedVenda(idFirebase: _saleR, itens: [
        VendaItem(
          produtoNome: 'prod-r',
          quantidade: 1,
          precoUnitario: 10,
          productId: 'prod-r',
          lojaId: _store,
        ),
      ]);
      backend.failRestore = true;
      Object? erro;
      try {
        await excluir(venda);
      } catch (e) {
        erro = e;
      }
      expect(erro, isNotNull);
      expect(erro, isNot(isA<VendaExclusaoAposEstornoException>()));
      final msg =
          EstoqueTransactionService.mensagemUsuarioFalhaDevolucaoEstoque(erro!);
      expect(msg, contains('Não foi possível devolver o estoque'));
      expect(await qtdCanonica('prod-r'), 4);
      expect(vendasBox.values.where((v) => v.idFirebase == _saleR),
          hasLength(1));
      expect(await VendaExclusaoTombstone.idsParaLoja(_store),
          isNot(contains(_saleR)));
      expect(await lixeiraCom(_saleR), 0);
    });
  });

  group('Fiado — exclusão com título a receber', () {
    test('restore falha → título aberto; retry → cancelado 1x, sem lançamentos',
        () async {
      const saleId = '0000000f-0000-4000-8000-00000000000f';
      const crId = 'cr_${saleId}_p1';
      await seedSimples('prod-f', qtd: 4);
      backend.seedAppliedSale(saleId, [
        {'productId': 'prod-f', 'quantity': 1},
      ]);
      final venda = await seedVenda(
        idFirebase: saleId,
        formas: 'Fiado',
        total: 50,
        itens: [
          VendaItem(
            produtoNome: 'prod-f',
            quantidade: 1,
            precoUnitario: 50,
            productId: 'prod-f',
            lojaId: _store,
          ),
        ],
      );
      await col(FSPaths.contasReceberCol).doc(crId).set({
        'lojaId': _store,
        'vendaIdFirebase': saleId,
        'valor': 50,
        'valorOriginal': 50,
        'saldoAtual': 50,
        'status': ContaReceberStatus.pendente,
        'pago': false,
      });
      final crBox = await ContaReceberService.openBoxLoja(_store);
      await crBox.add(
        ContaReceber(
          lojaId: _store,
          clienteNome: 'Cliente',
          valor: 50,
          dataVencimento: DateTime(2026, 11, 8),
          dataVenda: DateTime(2026, 10, 8),
          vendaKey: venda.key as int,
          idFirebase: crId,
          vendaIdFirebase: saleId,
        ),
      );

      backend.failRestore = true;
      await expectLater(excluir(venda), throwsA(anything));
      expect(crBox.values.where((c) => c.vendaIdFirebase == saleId),
          hasLength(1));
      final remotoAposFalha = await remoto(FSPaths.contasReceberCol, crId);
      expect(remotoAposFalha!['cancelada'], isNot(true));
      expect(remotoAposFalha['status'], ContaReceberStatus.pendente);
      expect(await qtdCanonica('prod-f'), 4);

      backend.failRestore = false;
      await excluir(venda);
      expect(backend.restoreApplied, 1);
      expect(await qtdCanonica('prod-f'), 5);
      expect(crBox.values.where((c) => c.vendaIdFirebase == saleId), isEmpty);
      final cancelado = await remoto(FSPaths.contasReceberCol, crId);
      expect(cancelado!['cancelada'], isTrue);
      expect(cancelado['status'], ContaReceberStatus.cancelada);

      await ContaReceberFirestoreService.cancelarContasReceberDaVenda(
        lojaId: _store,
        vendaIdFirebase: saleId,
      );
      final aposSegundo = await remoto(FSPaths.contasReceberCol, crId);
      expect(aposSegundo!['cancelada'], isTrue);
      expect(aposSegundo['status'], ContaReceberStatus.cancelada);

      final lancamentos = await fs
          .collection('lojas')
          .doc(_store)
          .collection('lancamentos_financeiros')
          .get();
      expect(lancamentos.docs, isEmpty);
      expect(await lixeiraCom(saleId), 1);
    });
  });

  group('Contrato de código', () {
    String ler(String p) => File(p).readAsStringSync();

    test('piso de combo não chama o estorno de venda sem source', () {
      final combo = ler('lib/services/combo_kit_stock_service.dart');
      expect(combo.contains('aplicarPisoEstoqueComboAposDevolucao'), isFalse);
      expect(combo.contains('vendaIdParaIdempotencia: null'), isFalse);
      expect(combo.contains('devolverEstoqueTransactionBatch'), isFalse);
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        expect(
          f.readAsStringSync().contains('aplicarPisoEstoqueComboAposDevolucao'),
          isFalse,
          reason: f.path,
        );
      }
    });

    test('scheduleVendaDelete: restore → contas → tombstone → delete', () {
      final src = ler('lib/services/soft_delete_service.dart');
      final start = src.indexOf('static Future<String?> scheduleVendaDelete');
      final body = src.substring(start);
      final restore = body.indexOf('devolverEstoqueParaVendaRemovida');
      final ok = body.indexOf('etapa=devolver_estoque_ok');
      final contas = body.indexOf('removerContasReceberVinculadasAVenda');
      final tomb = body.indexOf('VendaExclusaoTombstone.registrar');
      final del = body.indexOf('VendasFirestoreService.deleteVenda');
      final hiveDel = body.indexOf('vendasBox.delete(key)');
      expect(restore, greaterThan(0));
      expect(ok, greaterThan(restore));
      expect(contas, greaterThan(ok));
      expect(tomb, greaterThan(contas));
      expect(del, greaterThan(tomb));
      expect(hiveDel, greaterThan(del));
    });
  });
}