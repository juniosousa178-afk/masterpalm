// Idempotência de baixa PDV por operationId (Camada 1 M3.1).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:master_palm/services/vendas_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaId = 'loja-op-id-idempotencia';
const _opA = '11111111-2222-4333-8444-555555555501';
const _opB = '11111111-2222-4333-8444-555555555502';

Future<int> _qtdRemota(
  FakeFirebaseFirestore firestore,
  String productId,
) async {
  final snap = await firestore
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(productId)
      .get();
  return (snap.data()?['quantidade'] as num?)?.toInt() ?? -1;
}

Future<Map<String, dynamic>?> _marker(
  FakeFirebaseFirestore firestore,
  String operationId,
) async {
  final snap = await firestore
      .collection('lojas')
      .doc(_lojaId)
      .collection('estoque_baixa_pagamento')
      .doc(operationId)
      .get();
  return snap.data();
}

List<Map<String, dynamic>> _txItem({
  required String pid,
  required String nome,
  int qtd = 1,
  String tamanho = '',
  String cor = '',
}) =>
    [
      {
        'productId': pid,
        'nome': nome,
        'quantidade': qtd,
        if (tamanho.isNotEmpty) 'tamanho': tamanho,
        if (cor.isNotEmpty) 'cor': cor,
      },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late Box<Produto> produtosBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_op_id_idem_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProdutoExclusaoTombstoneService.resetCacheForTests();
    firestore = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = firestore;
    ProdutosFirestoreService.debugFirestoreOverride = firestore;
    final s = DateTime.now().microsecondsSinceEpoch;
    produtosBox = await Hive.openBox<Produto>('p_op_idem_$s');
  });

  tearDown(() async {
    EstoqueTransactionService.debugFirestoreOverride = null;
    ProdutosFirestoreService.debugFirestoreOverride = null;
    await produtosBox.close();
  });

  Future<void> seedSimples({
    required String pid,
    required int qtd,
    String nome = 'Prod',
  }) async {
    await firestore
        .collection('lojas')
        .doc(_lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({'nome': nome, 'quantidade': qtd});
    await produtosBox.add(
      Produto.vazio()
        ..nome = nome
        ..idFirebase = pid
        ..lojaId = _lojaId
        ..quantidade = qtd
        ..precoFinal = 10,
    );
  }

  group('baixarEstoqueTransactionBatchIdempotente', () {
    test('T1 — mesmo operationId 2× sequencial debita estoque uma vez', () async {
      const pid = 'prod-t1';
      await seedSimples(pid: pid, qtd: 5);

      final itens = _txItem(pid: pid, nome: 'Prod');

      final r1 =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );
      expect(r1.baixaAplicadaNestaExecucao, isTrue);
      expect(r1.baixaJaAplicadaAnteriormente, isFalse);

      final r2 =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );
      expect(r2.baixaJaAplicadaAnteriormente, isTrue);
      expect(await _qtdRemota(firestore, pid), 4);

      final m = await _marker(firestore, _opA);
      expect(m?['baixaAplicada'], isTrue);
      expect(m?['operationId'], _opA);
      expect(m?['saleId'], _opA);
      expect(m?['origem'], 'pdv');
    });

    test('T3 — operationIds diferentes debitam independentemente', () async {
      const pid = 'prod-t3';
      await seedSimples(pid: pid, qtd: 5);
      final itens = _txItem(pid: pid, nome: 'Prod');

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opB,
      );

      expect(await _qtdRemota(firestore, pid), 3);
    });

    test('T5 — marker já aplicado: replay sem nova baixa', () async {
      const pid = 'prod-t5';
      await seedSimples(pid: pid, qtd: 4);
      final itens = _txItem(pid: pid, nome: 'Prod');

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );
      expect(await _qtdRemota(firestore, pid), 3);

      final replay =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );
      expect(replay.baixaJaAplicadaAnteriormente, isTrue);
      expect(await _qtdRemota(firestore, pid), 3);
    });

    test('T-CONFLICT — mesmo operationId com efeito diferente fail-closed', () async {
      const pid = 'prod-conflict';
      await seedSimples(pid: pid, qtd: 5);

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _txItem(pid: pid, nome: 'Prod', qtd: 1),
        operationId: _opA,
      );

      await expectLater(
        EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
          lojaId: _lojaId,
          itens: _txItem(pid: pid, nome: 'Prod', qtd: 2),
          operationId: _opA,
        ),
        throwsA(isA<EstoqueBaixaOperationIdentityConflictException>()),
      );
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('T-VARIAÇÃO — replay em grade debita célula uma vez', () async {
      const pid = 'anel-var-t1';
      const tam = 'P';
      const cor = 'Azul';

      await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .set({
        'nome': 'Anel',
        'quantidade': 3,
        'variacoes': {
          tam: {cor: 2},
        },
      });

      final itens = _txItem(pid: pid, nome: 'Anel', tamanho: tam, cor: cor);

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: _opA,
      );

      final snap = await firestore
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(pid)
          .get();
      final vars = snap.data()?['variacoes'] as Map?;
      final cell = vars?[tam] as Map?;
      expect((cell?[cor] as num?)?.toInt(), 1);
      expect((snap.data()?['quantidade'] as num?)?.toInt(), 1);
    });

    test('estoque insuficiente não cria marker', () async {
      const pid = 'prod-sem-marker';
      await seedSimples(pid: pid, qtd: 0);
      final itens = _txItem(pid: pid, nome: 'Prod');

      await expectLater(
        EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
          lojaId: _lojaId,
          itens: itens,
          operationId: _opA,
        ),
        throwsA(isA<Exception>()),
      );

      final m = await _marker(firestore, _opA);
      expect(m, isNull);
    });
  });

  group('registrarVendaMulti — ownership rollback', () {
    late Box<Cliente> clientesBox;
    late Box<Venda> vendasBox;

    setUpAll(() async {
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ClienteAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(VendaAdapter());
      if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(VendaItemAdapter());
      if (!Hive.isAdapterRegistered(29)) {
        Hive.registerAdapter(ContaReceberAdapter());
      }
    });

    setUp(() async {
      LojaAtivaResolver.debugResolveOverride =
          ({String origem = 'app'}) async => _lojaId;
      ContaReceberFirestoreService.debugFirestoreOverride = firestore;
      final s = DateTime.now().microsecondsSinceEpoch;
      clientesBox = await Hive.openBox<Cliente>('c_op_idem_$s');
      vendasBox = await Hive.openBox<Venda>('v_op_idem_$s');
    });

    tearDown(() async {
      VendasService.debugVendasBoxAddOverride = null;
      VendasService.debugForcarFalhaEstornoPreHiveRollback = null;
      VendasService.debugOperacoesEmAndamentoClearForTests();
      LojaAtivaResolver.debugResolveOverride = null;
      ContaReceberFirestoreService.debugFirestoreOverride = null;
      await clientesBox.close();
      await vendasBox.close();
    });

    Future<Cliente> cliente() async {
      final c = Cliente(
        nome: 'Cli OpId',
        telefone: '11',
        instagram: '',
        cep: '',
        cidade: '',
        lojaId: _lojaId,
      );
      await clientesBox.add(c);
      return c;
    }

    test('T7 — baixa applied + falha Hive estorna estoque', () async {
      const pid = 'prod-t7';
      const opId = 'aaaaaaaa-bbbb-4ccc-dddd-eeeeeeeeee07';
      await seedSimples(pid: pid, qtd: 5);

      VendasService.debugVendasBoxAddOverride = (_, __) async {
        throw HiveError('falha hive');
      };

      final c = await cliente();
      await expectLater(
        VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: c.nome,
          clienteExistente: c,
          itens: [
            VendaItem(
              produtoNome: 'Prod',
              quantidade: 1,
              precoUnitario: 10,
              productId: pid,
            ),
          ],
          dinheiro: 10,
          lojaId: _lojaId,
          idFirebaseToReuse: opId,
        ),
        throwsA(isA<HiveError>()),
      );

      expect(vendasBox.length, 0);
      expect(await _qtdRemota(firestore, pid), 5);
    });

    test('T7B — alreadyApplied + falha Hive NÃO estorna baixa original', () async {
      const pid = 'prod-t7b';
      const opId = 'aaaaaaaa-bbbb-4ccc-dddd-eeeeeeeeee7b';
      await seedSimples(pid: pid, qtd: 5);
      final itens = _txItem(pid: pid, nome: 'Prod');

      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: itens,
        operationId: opId,
      );
      expect(await _qtdRemota(firestore, pid), 4);

      VendasService.debugVendasBoxAddOverride = (_, __) async {
        throw HiveError('falha hive replay');
      };

      final c = await cliente();
      await expectLater(
        VendasService.registrarVendaMulti(
          produtosBox: produtosBox,
          clientesBox: clientesBox,
          vendasBox: vendasBox,
          clienteNome: c.nome,
          clienteExistente: c,
          itens: [
            VendaItem(
              produtoNome: 'Prod',
              quantidade: 1,
              precoUnitario: 10,
              productId: pid,
            ),
          ],
          dinheiro: 10,
          lojaId: _lojaId,
          idFirebaseToReuse: opId,
        ),
        throwsA(isA<HiveError>()),
      );

      expect(vendasBox.length, 0);
      expect(await _qtdRemota(firestore, pid), 4);
    });

    test('T6 — fiado com operationId estável → 1 CR por parcela', () async {
      const pid = 'prod-fiado-t6';
      const opId = 'aaaaaaaa-bbbb-4ccc-dddd-eeeeeeeeee06';
      await seedSimples(pid: pid, qtd: 10);
      final c = await cliente();
      final venc = DateTime.now().add(const Duration(days: 30));
      final itens = [
        VendaItem(
          produtoNome: 'Prod',
          quantidade: 1,
          precoUnitario: 100,
          productId: pid,
        ),
      ];

      await VendasService.registrarVendaMulti(
        produtosBox: produtosBox,
        clientesBox: clientesBox,
        vendasBox: vendasBox,
        clienteNome: c.nome,
        clienteExistente: c,
        itens: itens,
        lojaId: _lojaId,
        isFiado: true,
        dataVencimentoFiado: venc,
        idFirebaseToReuse: opId,
      );

      final crBox = await Hive.openBox<ContaReceber>(
        HiveBoxNames.contasReceber(_lojaId),
      );
      final contas = crBox.values
          .where((c) => c.vendaIdFirebase == opId)
          .toList();
      expect(contas.length, 1);
      expect(resolveContaReceberDocId(contas.first), 'cr_${opId}_p1');

      final replay =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaId,
        itens: _txItem(pid: pid, nome: 'Prod'),
        operationId: opId,
      );
      expect(replay.baixaJaAplicadaAnteriormente, isTrue);
      expect(await _qtdRemota(firestore, pid), 9);
      await crBox.close();
    });
  });
}
