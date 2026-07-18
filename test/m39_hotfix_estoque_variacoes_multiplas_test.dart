// M3.9-HOTFIX-ESTOQUE-VARIACOES-MULTIPLAS-NA-MESMA-VENDA
// VARIACAO-ESTOQUE-1..14

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lojaA = 'loja-variacao-estoque-a';
const _lojaB = 'loja-variacao-estoque-b';
const _opA = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const _opB = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';

Future<Map<String, dynamic>?> _doc(
  FakeFirebaseFirestore db,
  String lojaId,
  String pid,
) async {
  final snap = await db
      .collection('lojas')
      .doc(lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(pid)
      .get();
  return snap.data();
}

int _cell(Map? vars, String tam, [String cor = 'sem-cor']) {
  final m = vars?[tam];
  if (m is! Map) return -1;
  final v = m[cor] ?? m['sem-cor'];
  if (v is num) return v.toInt();
  return -1;
}

List<Map<String, dynamic>> _itensPmg({
  required String pid,
  int p = 1,
  int m = 1,
  int g = 1,
}) =>
    [
      if (p > 0)
        {
          'productId': pid,
          'nome': 'Anel 1',
          'quantidade': p,
          'tamanho': 'P',
        },
      if (m > 0)
        {
          'productId': pid,
          'nome': 'Anel 1',
          'quantidade': m,
          'tamanho': 'M',
        },
      if (g > 0)
        {
          'productId': pid,
          'nome': 'Anel 1',
          'quantidade': g,
          'tamanho': 'G',
        },
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late Box<Produto> produtosBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_var_est_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = db;
    produtosBox = await Hive.openBox<Produto>(
      'p_var_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    EstoqueTransactionService.debugFirestoreOverride = null;
    if (produtosBox.isOpen) await produtosBox.close();
  });

  Future<void> seedAnel1({
    String lojaId = _lojaA,
    String pid = 'anel-1',
    int p = 5,
    int m = 5,
    int g = 5,
  }) async {
    final total = p + m + g;
    await db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({
      'nome': 'Anel 1',
      'quantidade': total,
      'slug': pid,
      'variacoes': {
        'P': {'sem-cor': p},
        'M': {'sem-cor': m},
        'G': {'sem-cor': g},
      },
      'estoquePorTamanho': {'P': p, 'M': m, 'G': g},
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Anel 1'
        ..idFirebase = pid
        ..slug = pid
        ..lojaId = lojaId
        ..quantidade = total
        ..precoFinal = 10
        ..variacoes = {
          'P': {'sem-cor': p},
          'M': {'sem-cor': m},
          'G': {'sem-cor': g},
        }
        ..estoquePorTamanho = {'P': p, 'M': m, 'G': g},
    );
  }

  Future<void> seedSimples({
    required String lojaId,
    required String pid,
    required int qtd,
  }) async {
    await db
        .collection('lojas')
        .doc(lojaId)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({'nome': 'Simples', 'quantidade': qtd, 'slug': pid});
    await produtosBox.add(
      Produto.vazio()
        ..nome = 'Simples'
        ..idFirebase = pid
        ..slug = pid
        ..lojaId = lojaId
        ..quantidade = qtd
        ..precoFinal = 10,
    );
  }

  group('VARIACAO-ESTOQUE chave canônica', () {
    test('stockItemKey distingue P/M/G do mesmo produto', () {
      final p = EstoqueTransactionService.stockItemKey(
        lojaId: _lojaA,
        produtoId: 'anel-1',
        tamanho: 'P',
      );
      final m = EstoqueTransactionService.stockItemKey(
        lojaId: _lojaA,
        produtoId: 'anel-1',
        tamanho: 'M',
      );
      final g = EstoqueTransactionService.stockItemKey(
        lojaId: _lojaA,
        produtoId: 'anel-1',
        tamanho: 'G',
      );
      expect(p, isNot(equals(m)));
      expect(m, isNot(equals(g)));
      expect(p, contains('anel-1'));
      expect(p, contains('|P|'));
    });
  });

  group('VARIACAO-ESTOQUE baixa batch', () {
    test('VARIACAO-ESTOQUE-1 P M G baixam as três', () async {
      await seedAnel1();
      final r = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-1'),
      );
      expect(r.length, 3);
      final data = await _doc(db, _lojaA, 'anel-1');
      expect(data?['quantidade'], 12);
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });

    test('VARIACAO-ESTOQUE-2 só variações vendidas mudam', () async {
      await seedAnel1();
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-1', p: 1, m: 0, g: 0),
      );
      final data = await _doc(db, _lojaA, 'anel-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 5);
    });

    test('VARIACAO-ESTOQUE-3 duas linhas P agregam', () async {
      await seedAnel1();
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: [
          {
            'productId': 'anel-1',
            'nome': 'Anel 1',
            'quantidade': 1,
            'tamanho': 'P',
          },
          {
            'productId': 'anel-1',
            'nome': 'Anel 1',
            'quantidade': 2,
            'tamanho': 'P',
          },
        ],
      );
      final data = await _doc(db, _lojaA, 'anel-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 2);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 5);
    });

    test('VARIACAO-ESTOQUE-4 mesmo produtoId + tamanho diferente não colide',
        () async {
      await seedAnel1();
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-1', p: 2, m: 1, g: 0),
      );
      final data = await _doc(db, _lojaA, 'anel-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 3);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 5);
    });

    test('VARIACAO-ESTOQUE-5 retry não baixa de novo', () async {
      await seedAnel1();
      final itens = _itensPmg(pid: 'anel-1');
      final r1 =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaA,
        itens: itens,
        operationId: _opA,
      );
      expect(r1.baixaAplicadaNestaExecucao, isTrue);
      final r2 =
          await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaA,
        itens: itens,
        operationId: _opA,
      );
      expect(r2.baixaJaAplicadaAnteriormente, isTrue);
      final data = await _doc(db, _lojaA, 'anel-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
      expect(data?['quantidade'], 12);
    });

    test('VARIACAO-ESTOQUE-6 falha total não deixa parcial; retry aplica tudo',
        () async {
      await seedAnel1();
      // Tentativa inválida (tamanho inexistente) não deve alterar P/M/G.
      await expectLater(
        () => EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: _lojaA,
          itens: [
            ..._itensPmg(pid: 'anel-1', p: 1, m: 0, g: 0),
            {
              'productId': 'anel-1',
              'nome': 'Anel 1',
              'quantidade': 1,
              'tamanho': 'XXL',
            },
          ],
        ),
        throwsA(isA<Exception>()),
      );
      var data = await _doc(db, _lojaA, 'anel-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 5);

      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-1'),
      );
      data = await _doc(db, _lojaA, 'anel-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });

    test('VARIACAO-ESTOQUE-7/8/9 caminhos admin/vendedor/catálogo = batch',
        () async {
      await seedAnel1(pid: 'anel-pdv');
      // Mesmo serviço usado por admin, vendedor e catálogo interno.
      final results =
          await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-pdv'),
      );
      expect(results.length, 3);
      final data = await _doc(db, _lojaA, 'anel-pdv');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });

    test('VARIACAO-ESTOQUE-10 offline sync = replay idempotente', () async {
      await seedAnel1(pid: 'anel-off');
      final itens = _itensPmg(pid: 'anel-off');
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaA,
        itens: itens,
        operationId: _opB,
      );
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _lojaA,
        itens: itens,
        operationId: _opB,
      );
      final data = await _doc(db, _lojaA, 'anel-off');
      expect(data?['quantidade'], 12);
    });

    test('VARIACAO-ESTOQUE-11 estorno devolve P M G', () async {
      await seedAnel1(pid: 'anel-est');
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-est'),
      );
      await EstoqueTransactionService.devolverEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-est'),
        vendaIdParaIdempotencia: 'venda-est-1',
      );
      final data = await _doc(db, _lojaA, 'anel-est');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 5);
      expect(data?['quantidade'], 15);

      // Retry estorno não duplica.
      await EstoqueTransactionService.devolverEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-est'),
        vendaIdParaIdempotencia: 'venda-est-1',
      );
      final data2 = await _doc(db, _lojaA, 'anel-est');
      expect(data2?['quantidade'], 15);
    });

    test('VARIACAO-ESTOQUE-12 produto sem variação continua ok', () async {
      await seedSimples(lojaId: _lojaA, pid: 'simples-1', qtd: 10);
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: [
          {'productId': 'simples-1', 'nome': 'Simples', 'quantidade': 3},
        ],
      );
      final data = await _doc(db, _lojaA, 'simples-1');
      expect(data?['quantidade'], 7);
    });

    test('VARIACAO-ESTOQUE-13 legado sem variacaoId usa tamanho/cor', () async {
      await seedAnel1(pid: 'anel-leg');
      // Sem campo variacaoId explícito — chave = produtoId|tamanho|cor|extra.
      final key = EstoqueTransactionService.stockItemKey(
        lojaId: _lojaA,
        produtoId: 'anel-leg',
        tamanho: 'P',
      );
      expect(key.endsWith('|P||'), isTrue);
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: [
          {
            'productId': 'anel-leg',
            'nome': 'Anel 1',
            'quantidade': 1,
            'tamanho': 'P',
          },
        ],
      );
      final data = await _doc(db, _lojaA, 'anel-leg');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
    });

    test('VARIACAO-ESTOQUE-14 duas lojas não colidem', () async {
      await seedAnel1(lojaId: _lojaA, pid: 'anel-shared');
      await seedAnel1(lojaId: _lojaB, pid: 'anel-shared');
      await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-shared'),
      );
      final a = await _doc(db, _lojaA, 'anel-shared');
      final b = await _doc(db, _lojaB, 'anel-shared');
      expect(a?['quantidade'], 12);
      expect(b?['quantidade'], 15);
      expect(_cell(b?['variacoes'] as Map?, 'P'), 5);
    });

    test('Hive espelha as três variações após batch', () async {
      await seedAnel1(pid: 'anel-hive');
      final results =
          await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _lojaA,
        itens: _itensPmg(pid: 'anel-hive'),
      );
      for (final r in results) {
        await EstoqueTransactionService.atualizarHiveAposTransacao(
          produtosBox: produtosBox,
          lojaId: _lojaA,
          result: r,
        );
      }
      final local = produtosBox.values.firstWhere(
        (p) => p.idFirebase == 'anel-hive',
      );
      expect(local.quantidade, 12);
      expect((local.variacoes?['P'] as Map?)?['sem-cor'], 4);
      expect((local.variacoes?['M'] as Map?)?['sem-cor'], 4);
      expect((local.variacoes?['G'] as Map?)?['sem-cor'], 4);
    });
  });
}
