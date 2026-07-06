// Recovery local do operationId após interrupção pré-Hive (M3.1-R).

import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/conta_receber_identity.dart';
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
import 'package:master_palm/services/venda_operation_journal_service.dart';
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-journal-recovery';

Future<int> _qtdRemota(FakeFirebaseFirestore fs, String pid) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

Future<Map<String, dynamic>?> _marker(FakeFirebaseFirestore fs, String opId) async {
  final snap = await fs
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_baixa_pagamento')
      .doc(opId)
      .get();
  return snap.data();
}

List<VendaItem> _itensSimples(String pid) => [
      VendaItem(
        produtoNome: 'Prod',
        quantidade: 1,
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
    hiveDir = await Directory.systemTemp.createTemp('hive_journal_rec_');
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
      nome: 'Cli Journal',
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
    String? idFirebaseToReuse,
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
      idFirebaseToReuse: idFirebaseToReuse,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    VendasService.debugOperacoesEmAndamentoClearForTests();
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_jr_$s');
    clientesBox = await Hive.openBox<Cliente>('c_jr_$s');
    vendasBox = await Hive.openBox<Venda>('v_jr_$s');
    journalBox = await Hive.openBox<Map>(
      HiveBoxNames.vendaOperationJournal(_lojaId),
    );
    await journalBox.clear();
    VendaOperationJournalService.debugBoxOverride = journalBox;
  });

  tearDown(() async {
    VendasService.debugVendasBoxAddOverride = null;
    VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
    VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
    VendasService.debugOperacoesEmAndamentoClearForTests();
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

  group('VendaOperationJournalService — J1–J7', () {
    test('J1 reserveOrRecover mesma operationKey → mesmo operationId', () async {
      const hash = 'abc123hash';
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      final e1 = await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
      );
      final e2 = await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
      );
      expect(e2.operationId, e1.operationId);
    });

    test('J2 complete remove pending', () async {
      const hash = 'hash-complete';
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.complete(
        lojaId: _lojaId,
        operationKey: key,
      );
      expect(
        await VendaOperationJournalService.findPending(
          lojaId: _lojaId,
          operationKey: key,
        ),
        isNull,
      );
    });

    test('J3 revert remove pending', () async {
      const hash = 'hash-revert';
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.revert(
        lojaId: _lojaId,
        operationKey: key,
      );
      expect(journalBox.get(key), isNull);
    });

    test('J4 critical preserva entry', () async {
      const hash = 'hash-critical';
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.markCritical(
        lojaId: _lojaId,
        operationKey: key,
      );
      final pending = await VendaOperationJournalService.findPending(
        lojaId: _lojaId,
        operationKey: key,
      );
      expect(pending?.critical, isTrue);
    });

    test('J5 operationKeys diferentes não colidem', () async {
      final k1 = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: 'hash-a',
      );
      final k2 = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: 'hash-b',
      );
      final e1 = await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: k1,
        stockEffectHash: 'hash-a',
      );
      final e2 = await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: k2,
        stockEffectHash: 'hash-b',
      );
      expect(e1.operationId, isNot(e2.operationId));
      expect(journalBox.length, 2);
    });

    test('J6 box isolada por loja', () async {
      const lojaA = 'loja-journal-a';
      const lojaB = 'loja-journal-b';
      const hash = 'hash-loja-iso';
      final keyA = VendaOperationJournalService.buildOperationKey(
        lojaId: lojaA,
        stockEffectHash: hash,
      );
      final keyB = VendaOperationJournalService.buildOperationKey(
        lojaId: lojaB,
        stockEffectHash: hash,
      );
      final boxA = await Hive.openBox<Map>(HiveBoxNames.vendaOperationJournal(lojaA));
      final boxB = await Hive.openBox<Map>(HiveBoxNames.vendaOperationJournal(lojaB));
      VendaOperationJournalService.debugBoxOverride = boxA;
      final eA = await VendaOperationJournalService.reserveOrRecover(
        lojaId: lojaA,
        operationKey: keyA,
        stockEffectHash: hash,
      );
      VendaOperationJournalService.debugBoxOverride = boxB;
      final eB = await VendaOperationJournalService.reserveOrRecover(
        lojaId: lojaB,
        operationKey: keyB,
        stockEffectHash: hash,
      );
      expect(eA.operationId, isNot(eB.operationId));
      expect(boxA.get(keyA), isNotNull);
      expect(boxB.get(keyB), isNotNull);
      await boxA.close();
      await boxB.close();
    });

    test('J7 payload não contém cliente/pagamentos/observação', () async {
      const hash = 'hash-privacy';
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
      );
      final raw = jsonEncode(journalBox.get(key));
      expect(raw.contains('cliente'), isFalse);
      expect(raw.contains('observacao'), isFalse);
      expect(raw.contains('pagamento'), isFalse);
    });
  });

  group('registrarVendaMulti — recovery R1–R6', () {
    test('R1 crash pós-baixa pré-Hive → retry recupera operationId', () async {
      const pid = 'prod-r1';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      final itens = _itensSimples(pid);

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };

      await expectLater(
        registrar(c: c, itens: itens),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      expect(vendasBox.length, 0);
      expect(await _qtdRemota(firestore, pid), 4);
      expect(journalBox.isNotEmpty, isTrue);

      final pendingKey = journalBox.keys.first as String;
      final opId =
          (journalBox.get(pendingKey) as Map)['operationId'] as String;
      expect((await _marker(firestore, opId))?['baixaAplicada'], isTrue);

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final venda = await registrar(c: c, itens: itens);
      expect(venda.idFirebase, opId);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), 4);
      expect(journalBox.isEmpty, isTrue);
    });

    test('R2 venda idêntica após conclusão → novo operationId', () async {
      const pid = 'prod-r2';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final itens = _itensSimples(pid);

      final v1 = await registrar(c: c, itens: itens);
      final v2 = await registrar(c: c, itens: itens);
      expect(v1.idFirebase, isNot(equals(v2.idFirebase)));
      expect(vendasBox.length, 2);
      expect(await _qtdRemota(firestore, pid), 8);
    });

    test('R3 hash divergente não reutiliza journal antigo', () async {
      const pidA = 'prod-r3a';
      const pidB = 'prod-r3b';
      await seedProduto(pid: pidA);
      await seedProduto(pid: pidB);

      final txA = [
        {'productId': pidA, 'nome': 'Prod', 'quantidade': 1},
      ];
      final hashA =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(txA);
      final keyA = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hashA,
      );
      final entryA = await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: keyA,
        stockEffectHash: hashA,
      );

      final c = await seedCliente();
      final vB = await registrar(c: c, itens: _itensSimples(pidB));
      expect(vB.idFirebase, isNot(entryA.operationId));
      expect(
        await VendaOperationJournalService.findPending(
          lojaId: _lojaId,
          operationKey: keyA,
        ),
        isNotNull,
      );
    });

    test('R4 alreadyApplied + falha Hive não estorna e journal permanece', () async {
      const pid = 'prod-r4';
      const opId = 'aaaaaaaa-bbbb-4ccc-dddd-eeeeeeeeee04';
      await seedProduto(pid: pid);
      final txItems = [
        {'productId': pid, 'nome': 'Prod', 'quantidade': 1},
      ];
      final hash =
          EstoqueTransactionService.computeTxItemsHashForIdempotencia(txItems);
      final key = VendaOperationJournalService.buildOperationKey(
        lojaId: _lojaId,
        stockEffectHash: hash,
      );
      await VendaOperationJournalService.reserveOrRecover(
        lojaId: _lojaId,
        operationKey: key,
        stockEffectHash: hash,
        explicitOperationId: opId,
      );
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: txItems,
        operationId: opId,
      );
      expect(await _qtdRemota(firestore, pid), 4);

      VendasService.debugVendasBoxAddOverride = (_, __) async {
        throw HiveError('falha hive r4');
      };
      final c = await seedCliente();
      await expectLater(
        registrar(c: c, itens: _itensSimples(pid)),
        throwsA(isA<HiveError>()),
      );
      expect(await _qtdRemota(firestore, pid), 4);
      expect(
        await VendaOperationJournalService.findPending(
          lojaId: _lojaId,
          operationKey: key,
        ),
        isNotNull,
      );
    });

    test('R5 applied + falha Hive + rollback OK remove journal', () async {
      const pid = 'prod-r5';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      VendasService.debugVendasBoxAddOverride = (_, __) async {
        throw HiveError('falha hive r5');
      };
      await expectLater(
        registrar(c: c, itens: _itensSimples(pid)),
        throwsA(isA<HiveError>()),
      );
      expect(await _qtdRemota(firestore, pid), 5);
      expect(journalBox.isEmpty, isTrue);
    });

    test('R6 rollback falha → crítica e journal preservado', () async {
      const pid = 'prod-r6';
      await seedProduto(pid: pid);
      final c = await seedCliente();
      VendasService.debugVendasBoxAddOverride = (_, __) async {
        throw HiveError('falha hive r6');
      };
      VendasService.debugForcarFalhaEstornoPreHiveRollback = () async {
        throw StateError('estorno falhou');
      };
      await expectLater(
        registrar(c: c, itens: _itensSimples(pid)),
        throwsA(isA<VendaPersistenciaInconsistenciaCritica>()),
      );
      expect(journalBox.isNotEmpty, isTrue);
      final entry = VendaOperationJournalEntry.fromMap(journalBox.values.first);
      expect(entry?.critical, isTrue);
    });
  });

  group('recovery R7 fiado', () {
    test('R7 fiado crash recovery mantém 1 CR', () async {
      const pid = 'prod-r7-fiado';
      await seedProduto(pid: pid, qtd: 10);
      final c = await seedCliente();
      final venc = DateTime.now().add(const Duration(days: 30));

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrar(
          c: c,
          itens: [
            VendaItem(
              produtoNome: 'Prod',
              quantidade: 1,
              precoUnitario: 100,
              productId: pid,
            ),
          ],
          isFiado: true,
          vencimento: venc,
        ),
        throwsA(isA<VendaOperationInterruptedException>()),
      );

      final opId = journalBox.values.first['operationId'] as String;
      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      await registrar(
        c: c,
        itens: [
          VendaItem(
            produtoNome: 'Prod',
            quantidade: 1,
            precoUnitario: 100,
            productId: pid,
          ),
        ],
        isFiado: true,
        vencimento: venc,
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(_lojaId),
      );
      final contas =
          crBox.values.where((c) => c.vendaIdFirebase == opId).toList();
      expect(contas.length, 1);
      expect(resolveContaReceberDocId(contas.first), 'cr_${opId}_p1');
      expect(await _qtdRemota(firestore, pid), 9);
      await crBox.close();
    });
  });

  group('recovery R8 variação', () {
    test('R8 grade crash recovery debita célula 1×', () async {
      const pid = 'anel-r8';
      const tam = 'P';
      const cor = 'Azul';
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({
        'nome': 'Anel R8',
        'quantidade': 3,
        'variacoes': {tam: {cor: 2}},
        'estoquePorTamanho': {tam: 2},
      });
      await produtosBox.add(
        Produto(
          nome: 'Anel R8',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 50,
          quantidade: 3,
          precoUnitario: 50,
          categoria: '',
          dataEntrada: DateTime(2026, 6, 1),
          lojaId: _lojaId,
          idFirebase: pid,
          variacoes: {tam: {cor: 2}},
        ),
      );
      final c = await seedCliente();
      final itens = [
        VendaItem(
          produtoNome: 'Anel R8',
          quantidade: 1,
          precoUnitario: 50,
          productId: pid,
          tamanho: tam,
          cor: cor,
        ),
      ];

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrar(c: c, itens: itens, dinheiro: 50),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      final opId = journalBox.values.first['operationId'] as String;
      final snap1 = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      expect((snap1.data()?['quantidade'] as num?)?.toInt(), 1);
      final vars1 = snap1.data()?['variacoes'] as Map?;
      expect((vars1?[tam] as Map?)?[cor], 1);

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final venda = await registrar(c: c, itens: itens, dinheiro: 50);
      expect(venda.idFirebase, opId);
      expect(vendasBox.length, 1);
      final snap2 = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      final vars = snap2.data()?['variacoes'] as Map?;
      expect((vars?[tam] as Map?)?[cor], 1);
      expect((snap2.data()?['quantidade'] as num?)?.toInt(), 1);
    });
  });

  group('recovery R9 combo/componentes', () {
    test('R9 combo crash recovery debita componente 1×', () async {
      const idPingente = 'comp-r9';
      const idCombo = 'combo-r9';
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idPingente)
          .set({'nome': 'Pingente R9', 'quantidade': 10});
      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(idCombo)
          .set({'nome': 'Colar Combo R9', 'quantidade': 10});

      await produtosBox.addAll([
        Produto.vazio()
          ..nome = 'Pingente R9'
          ..idFirebase = idPingente
          ..lojaId = _lojaId
          ..quantidade = 10
          ..precoFinal = 10,
        Produto.vazio()
          ..nome = 'Colar Combo R9'
          ..idFirebase = idCombo
          ..lojaId = _lojaId
          ..tipoProduto = 'combo'
          ..quantidade = 10
          ..precoFinal = 100
          ..itensCombo = [
            {'productId': idPingente, 'nome': 'Pingente R9', 'quantidade': 1},
          ],
      ]);

      final c = await seedCliente();
      final itens = [
        VendaItem(
          produtoNome: 'Pingente R9',
          quantidade: 2,
          precoUnitario: 10,
          productId: idPingente,
        ),
      ];

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = () async {
        throw const VendaOperationInterruptedException();
      };
      await expectLater(
        registrar(c: c, itens: itens, dinheiro: 20),
        throwsA(isA<VendaOperationInterruptedException>()),
      );
      final opId = journalBox.values.first['operationId'] as String;
      expect(await _qtdRemota(firestore, idPingente), 8);

      VendasService.debugAfterRemoteStockAppliedBeforeHivePersist = null;
      final venda = await registrar(c: c, itens: itens, dinheiro: 20);
      expect(venda.idFirebase, opId);
      expect(await _qtdRemota(firestore, idPingente), 8);
      expect(await _qtdRemota(firestore, idCombo), 8);
      expect(vendasBox.length, 1);
    });
  });

  group('contrato estrutural journal antes da baixa', () {
    test('journal reserveOrRecover precede baixa idempotente no código', () {
      final src = File('lib/services/vendas_service.dart').readAsStringSync();
      final iJournal = src.indexOf('VendaOperationJournalService.reserveOrRecover');
      final iBaixa = src.indexOf('baixarEstoqueTransactionBatchIdempotente');
      expect(iJournal, greaterThan(-1));
      expect(iBaixa, greaterThan(iJournal));
    });
  });
}
