// M3.2-B.1 — M32B-14: fiado coordenado + ContaReceber + Sale Intent revert/critical.

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

const _lojaId = 'loja-m32b-14-fiado';
const _intentId = 'intent-m32b-14-fiado';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late Directory hiveDir;
  late Box<Produto> produtosBox;
  late Box<Cliente> clientesBox;
  late Box<Venda> vendasBox;
  late Box<Map> journalBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hive_m32b_14_');
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
        .set({'nome': 'Prod Fiado', 'quantidade': qtd});
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Prod Fiado'
        ..idFirebase = pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 40,
    );
  }

  Future<Cliente> seedCliente() async {
    final c = Cliente(
      nome: 'Cli Fiado M32B14',
      telefone: '11',
      instagram: '',
      cep: '',
      cidade: '',
      lojaId: _lojaId,
    );
    await clientesBox.add(c);
    return c;
  }

  Future<Venda> registrarFiadoCoordenado({
    required Cliente c,
    required String pid,
    int qtd = 2,
  }) {
    return VendasService.registrarVendaMulti(
      produtosBox: produtosBox,
      clientesBox: clientesBox,
      vendasBox: vendasBox,
      clienteNome: c.nome,
      clienteExistente: c,
      itens: [
        VendaItem(
          produtoNome: 'Prod Fiado',
          quantidade: qtd,
          precoUnitario: 40,
          productId: pid,
        ),
      ],
      lojaId: _lojaId,
      isFiado: true,
      dataVencimentoFiado: DateTime.now().add(const Duration(days: 30)),
      saleIntentId: _intentId,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    VendasService.debugOperacoesEmAndamentoClearForTests();
    VendasService.debugPersistirContasReceberNaBoxOverride = null;
    VendasService.debugForcarFalhaEstornoPosFiadoRollback = null;
    SaleIntentService.debugClearOverride();
    LojaAtivaResolver.debugResolveOverride =
        ({String origem = 'app'}) async => _lojaId;
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    SaleIntentService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    ContaReceberFirestoreService.debugFirestoreOverride = firestore;

    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_m32b14_$s');
    clientesBox = await Hive.openBox<Cliente>('c_m32b14_$s');
    vendasBox = await Hive.openBox<Venda>('v_m32b14_$s');
    journalBox = await Hive.openBox<Map>(
      HiveBoxNames.vendaOperationJournal(_lojaId),
    );
    await journalBox.clear();
    VendaOperationJournalService.debugBoxOverride = journalBox;
  });

  tearDown(() async {
    VendasService.debugPersistirContasReceberNaBoxOverride = null;
    VendasService.debugForcarFalhaEstornoPosFiadoRollback = null;
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

  group('M32B-14 fiado coordenado + ContaReceber', () {
    test('M32B-14A falha CR + rollback OK → reverted + retry converge', () async {
      const pid = 'prod-m32b-14a';
      const qtdInicial = 5;
      await seedProduto(pid: pid, qtd: qtdInicial);
      final c = await seedCliente();

      VendasService.debugPersistirContasReceberNaBoxOverride =
          ({required crBox, required contas, required lojaId, required vendaIdVinculo, required vendaHiveKey}) async {
        throw StateError('falha simulada persistência ContaReceber');
      };

      await expectLater(
        registrarFiadoCoordenado(c: c, pid: pid),
        throwsA(isA<ArgumentError>()),
      );

      expect(await _qtdRemota(firestore, pid), qtdInicial);
      expect(vendasBox.length, 0);

      final crBox =
          await Hive.openBox<ContaReceber>(HiveBoxNames.contasReceber(_lojaId));
      expect(crBox.length, 0);
      await crBox.close();

      final intentFail = await _saleIntent(firestore, _intentId);
      expect(intentFail!['status'], 'reverted');
      final opId = intentFail['operationId'] as String;
      expect(opId, isNotEmpty);

      VendasService.debugPersistirContasReceberNaBoxOverride = null;

      final venda = await registrarFiadoCoordenado(c: c, pid: pid);
      expect(venda.idFirebase, opId);
      expect(vendasBox.length, 1);
      expect(await _qtdRemota(firestore, pid), qtdInicial - 2);

      final crBox2 =
          await Hive.openBox<ContaReceber>(HiveBoxNames.contasReceber(_lojaId));
      expect(crBox2.length, 1);
      await crBox2.close();

      final intentOk = await _saleIntent(firestore, _intentId);
      expect(intentOk!['status'], 'completed');
      expect(intentOk['operationId'], opId);

      final m = await _marker(firestore, opId);
      expect(m?['baixaAplicada'], isTrue);
    });

    test('M32B-14B falha CR + falha estorno → critical', () async {
      const pid = 'prod-m32b-14b';
      const qtdInicial = 5;
      await seedProduto(pid: pid, qtd: qtdInicial);
      final c = await seedCliente();

      VendasService.debugPersistirContasReceberNaBoxOverride =
          ({required crBox, required contas, required lojaId, required vendaIdVinculo, required vendaHiveKey}) async {
        throw StateError('falha CR simulada 14B');
      };
      VendasService.debugForcarFalhaEstornoPosFiadoRollback = () async {
        throw StateError('falha estorno fiado simulada 14B');
      };

      Object? caught;
      try {
        await registrarFiadoCoordenado(c: c, pid: pid);
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<VendaPersistenciaInconsistenciaCritica>());
      final crit = caught! as VendaPersistenciaInconsistenciaCritica;
      expect(crit.erroPersistencia, isA<StateError>());
      expect(crit.erroEstorno, isA<StateError>());

      final intent = await _saleIntent(firestore, _intentId);
      expect(intent!['status'], 'critical');
      expect(intent['status'], isNot('reverted'));
      expect(intent['status'], isNot('completed'));

      final opId = intent['operationId'] as String;
      expect(opId, isNotEmpty);
      expect(await _qtdRemota(firestore, pid), qtdInicial - 2);
      expect(vendasBox.length, 1);
    });

    test('M32B-14C NÃO APLICÁVEL — falha antes de escrita parcial CR', () {
      final src = File('lib/services/vendas_service.dart').readAsStringSync();
      final iPersist = src.indexOf('static Future<void> _persistirContasReceberNaBox');
      expect(iPersist, greaterThan(0));
      final body = src.substring(iPersist, iPersist + 1200);
      expect(body.contains('await crBox.add(conta)'), isTrue);
      expect(
        body.indexOf('await crBox.add(conta)') <
            body.indexOf('ContaReceberFirestoreService.upsertContaReceber'),
        isTrue,
        reason: 'CR Hive add ocorre antes do upsert Firestore; falha no override '
            'simula falha antes de qualquer escrita — equivalente a 14A',
      );
    });
  });
}
