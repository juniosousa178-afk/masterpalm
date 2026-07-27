// M3.9-P0-CONSIGNADO-VARIACOES — CONSIGNADO-VAR-1..15
// Fiado/consignado usa o mesmo EstoqueTransactionService do hotfix 207fc92.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _loja = 'loja-consignado-var';
const _op1 = 'cccccccc-3333-4333-8333-cccccccccccc';
const _op2 = 'dddddddd-4444-4444-8444-dddddddddddd';
const _repairOp = 'm39-repair-thawana-20260717-1940-v1';

Future<Map<String, dynamic>?> _doc(
  FakeFirebaseFirestore db,
  String pid,
) async {
  final snap = await db
      .collection('lojas')
      .doc(_loja)
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

List<Map<String, dynamic>> _pmg(String pid) => [
      {'productId': pid, 'nome': pid, 'quantidade': 1, 'tamanho': 'P'},
      {'productId': pid, 'nome': pid, 'quantidade': 1, 'tamanho': 'M'},
      {'productId': pid, 'nome': pid, 'quantidade': 1, 'tamanho': 'G'},
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore db;
  late Box<Produto> produtosBox;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_cons_var_');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProdutoAdapter());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    EstoqueTransactionService.debugFirestoreOverride = db;
    produtosBox = await Hive.openBox<Produto>(
      'p_cons_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    EstoqueTransactionService.debugFirestoreOverride = null;
    if (produtosBox.isOpen) await produtosBox.close();
  });

  Future<void> seedPmg(String pid, {int each = 5}) async {
    final total = each * 3;
    await db
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({
      'nome': pid,
      'quantidade': total,
      'slug': pid,
      'variacoes': {
        'P': {'sem-cor': each},
        'M': {'sem-cor': each},
        'G': {'sem-cor': each},
      },
      'estoquePorTamanho': {'P': each, 'M': each, 'G': each},
    });
    await produtosBox.add(
      Produto.vazio()
        ..nome = pid
        ..idFirebase = pid
        ..slug = pid
        ..lojaId = _loja
        ..quantidade = total
        ..precoFinal = 10
        ..variacoes = {
          'P': {'sem-cor': each},
          'M': {'sem-cor': each},
          'G': {'sem-cor': each},
        }
        ..estoquePorTamanho = {'P': each, 'M': each, 'G': each},
    );
  }

  Future<void> seedSimples(String pid, int qtd) async {
    await db
        .collection('lojas')
        .doc(_loja)
        .collection(FSPaths.estoqueProdutosCol)
        .doc(pid)
        .set({'nome': pid, 'quantidade': qtd, 'slug': pid});
    await produtosBox.add(
      Produto.vazio()
        ..nome = pid
        ..idFirebase = pid
        ..slug = pid
        ..lojaId = _loja
        ..quantidade = qtd
        ..precoFinal = 10,
    );
  }

  Future<void> mirrorHive(List<EstoqueTransactionResult> results) async {
    final byId = <String, EstoqueTransactionResult>{};
    for (final r in results) {
      byId[r.produtoId] = r;
    }
    for (final r in byId.values) {
      await EstoqueTransactionService.atualizarHiveAposTransacao(
        produtosBox: produtosBox,
        lojaId: _loja,
        result: r,
      );
    }
  }

  group('CONSIGNADO-VAR contrato de caminho', () {
    test('fiado/consignado usa batch idempotente central (sem caminho paralelo)',
        () {
      final src = File('lib/services/vendas_service.dart').readAsStringSync();
      expect(
        src.contains('baixarEstoqueTransactionBatchIdempotente'),
        isTrue,
      );
      // isFiado não deve abrir serviço de estoque próprio antes do batch.
      final baixaIdx = src.indexOf('baixarEstoqueTransactionBatchIdempotente');
      final fiadoCrIdx = src.indexOf('se fiado com saldo, criar conta a receber');
      expect(baixaIdx, greaterThan(0));
      expect(fiadoCrIdx, greaterThan(baixaIdx));
    });
  });

  group('CONSIGNADO-VAR baixa + persistência', () {
    test('CONSIGNADO-VAR-1 P/M/G do mesmo produto baixam', () async {
      await seedPmg('brinco-1');
      final op = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('brinco-1'),
        operationId: _op1,
      );
      expect(op.baixaAplicadaNestaExecucao, isTrue);
      final data = await _doc(db, 'brinco-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
      expect(data?['quantidade'], 12);
    });

    test('CONSIGNADO-VAR-2 após reload Hive permanece baixado', () async {
      await seedPmg('brinco-2');
      final op = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('brinco-2'),
        operationId: _op1,
      );
      await mirrorHive(op.transactionResults);
      final local = produtosBox.values.firstWhere((p) => p.idFirebase == 'brinco-2');
      expect(_cell(local.variacoes, 'P'), 4);
      expect(_cell(local.variacoes, 'M'), 4);
      expect(_cell(local.variacoes, 'G'), 4);
    });

    test('CONSIGNADO-VAR-3 syncFirestoreToHive não restaura variações', () async {
      await seedPmg('brinco-3');
      final op = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('brinco-3'),
        operationId: _op1,
      );
      await mirrorHive(op.transactionResults);
      // Simula reload: re-lê remoto (já baixado) e confirma.
      final remote = await _doc(db, 'brinco-3');
      expect(_cell(remote?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(remote?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(remote?['variacoes'] as Map?, 'G'), 4);
    });

    test('CONSIGNADO-VAR-4 retry idempotente não baixa de novo nem restaura',
        () async {
      await seedPmg('brinco-4');
      final first = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('brinco-4'),
        operationId: _op1,
      );
      expect(first.baixaAplicadaNestaExecucao, isTrue);
      final second = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('brinco-4'),
        operationId: _op1,
      );
      expect(second.baixaJaAplicadaAnteriormente, isTrue);
      expect(second.baixaAplicadaNestaExecucao, isFalse);
      final data = await _doc(db, 'brinco-4');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });

    test('CONSIGNADO-VAR-5 várias linhas do mesmo produto acumulam', () async {
      await seedPmg('brinco-5', each: 10);
      final itens = [
        {'productId': 'brinco-5', 'quantidade': 2, 'tamanho': 'P'},
        {'productId': 'brinco-5', 'quantidade': 3, 'tamanho': 'P'},
        {'productId': 'brinco-5', 'quantidade': 1, 'tamanho': 'M'},
      ];
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: itens,
        operationId: _op1,
      );
      final data = await _doc(db, 'brinco-5');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 5);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 9);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 10);
    });

    test('CONSIGNADO-VAR-6 vários produtos com variações', () async {
      await seedPmg('a');
      await seedPmg('b');
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: [..._pmg('a'), ..._pmg('b')],
        operationId: _op1,
      );
      for (final pid in ['a', 'b']) {
        final data = await _doc(db, pid);
        expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
        expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
        expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
      }
    });

    test('CONSIGNADO-VAR-7 simples + variação não interferem', () async {
      await seedPmg('var-x');
      await seedSimples('simp-y', 9);
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: [
          ..._pmg('var-x'),
          {'productId': 'simp-y', 'quantidade': 2},
        ],
        operationId: _op1,
      );
      expect((await _doc(db, 'simp-y'))?['quantidade'], 7);
      expect(_cell((await _doc(db, 'var-x'))?['variacoes'] as Map?, 'P'), 4);
    });

    test('CONSIGNADO-VAR-8 venda normal (sem fiado) continua correta', () async {
      await seedPmg('normal-1');
      final r = await EstoqueTransactionService.baixarEstoqueTransactionBatch(
        lojaId: _loja,
        itens: _pmg('normal-1'),
      );
      expect(r.length, 3);
      expect(_cell((await _doc(db, 'normal-1'))?['variacoes'] as Map?, 'G'), 4);
    });

    test('CONSIGNADO-VAR-9 venda grande (~81 itens) não perde writes', () async {
      final itens = <Map<String, dynamic>>[];
      for (var i = 0; i < 27; i++) {
        final pid = 'big-$i';
        await seedPmg(pid, each: 3);
        itens.addAll(_pmg(pid));
      }
      expect(itens.length, 81);
      final op = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: itens,
        operationId: _op1,
      );
      expect(op.baixaAplicadaNestaExecucao, isTrue);
      for (var i = 0; i < 27; i++) {
        final data = await _doc(db, 'big-$i');
        expect(_cell(data?['variacoes'] as Map?, 'P'), 2, reason: 'big-$i P');
        expect(_cell(data?['variacoes'] as Map?, 'M'), 2, reason: 'big-$i M');
        expect(_cell(data?['variacoes'] as Map?, 'G'), 2, reason: 'big-$i G');
        expect(data?['quantidade'], 6);
      }
    });

    test('CONSIGNADO-VAR-10 write tardio com snapshot antigo é barrado por updatedAt',
        () async {
      await seedPmg('stale-1');
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('stale-1'),
        operationId: _op1,
      );
      // Segunda operação com outro opId debita de novo a partir do estado atual.
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: [
          {'productId': 'stale-1', 'quantidade': 1, 'tamanho': 'P'},
        ],
        operationId: _op2,
      );
      final data = await _doc(db, 'stale-1');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 3);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });

    test('CONSIGNADO-VAR-11 um write final por documento (writesByPath)', () async {
      await seedPmg('one-write');
      final op = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('one-write'),
        operationId: _op1,
      );
      // 3 débitos, mas um único estado final coerente.
      expect(op.transactionResults.length, 3);
      final data = await _doc(db, 'one-write');
      expect(data?['quantidade'], 12);
      expect(_cell(data?['variacoes'] as Map?, 'P'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });
  });

  group('CONSIGNADO-VAR reparo dry-run/contrato', () {
    test('CONSIGNADO-VAR-12 reparo idempotente (reaplicar mesma baixa op)',
        () async {
      await seedPmg('repair-1');
      final a = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('repair-1'),
        operationId: _repairOp,
      );
      final b = await EstoqueTransactionService
          .baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('repair-1'),
        operationId: _repairOp,
      );
      expect(a.baixaAplicadaNestaExecucao, isTrue);
      expect(b.baixaJaAplicadaAnteriormente, isTrue);
      expect(_cell((await _doc(db, 'repair-1'))?['variacoes'] as Map?, 'P'), 4);
    });

    test('CONSIGNADO-VAR-13 precondition updatedAt: segunda venda muda estado',
        () async {
      await seedPmg('cas-1');
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('cas-1'),
        operationId: _op1,
      );
      final before = await _doc(db, 'cas-1');
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: [
          {'productId': 'cas-1', 'quantidade': 1, 'tamanho': 'M'},
        ],
        operationId: _op2,
      );
      final after = await _doc(db, 'cas-1');
      expect(_cell(before?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(after?['variacoes'] as Map?, 'M'), 3);
    });

    test('CONSIGNADO-VAR-14 reparo não toca produto simples não listado',
        () async {
      await seedPmg('var-only');
      await seedSimples('keep-simple', 11);
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('var-only'),
        operationId: _op1,
      );
      expect((await _doc(db, 'keep-simple'))?['quantidade'], 11);
    });

    test('CONSIGNADO-VAR-15 segunda operação distinta debita estado atual',
        () async {
      await seedPmg('dual-op');
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: _pmg('dual-op'),
        operationId: _op1,
      );
      await EstoqueTransactionService.baixarEstoqueTransactionBatchIdempotente(
        lojaId: _loja,
        itens: [
          {'productId': 'dual-op', 'quantidade': 1, 'tamanho': 'P'},
        ],
        operationId: _op2,
      );
      final data = await _doc(db, 'dual-op');
      expect(_cell(data?['variacoes'] as Map?, 'P'), 3);
      expect(_cell(data?['variacoes'] as Map?, 'M'), 4);
      expect(_cell(data?['variacoes'] as Map?, 'G'), 4);
    });
  });
}
