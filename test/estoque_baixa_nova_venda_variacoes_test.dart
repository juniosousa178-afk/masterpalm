import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';

const _lojaId = 'loja-baixa-venda-test';

Future<void> _seedProduto(
  FakeFirebaseFirestore db, {
  required String docId,
  required Map<String, dynamic> data,
}) async {
  final ref = db
      .collection('lojas')
      .doc(_lojaId)
      .collection(FSPaths.estoqueProdutosCol)
      .doc(docId);
  await ref.set(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nova Venda — baixa Firestore com deletes de grade', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = FakeFirebaseFirestore();
      EstoqueTransactionService.debugFirestoreOverride = db;
    });

    tearDown(() {
      EstoqueTransactionService.debugFirestoreOverride = null;
    });

    test('produto simples reduz quantidade total', () async {
      const docId = 'prod-simples';
      await _seedProduto(db, docId: docId, data: {
        'nome': 'Pulseira Simples',
        'quantidade': 10,
        'slug': docId,
      });

      final r = await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: _lojaId,
        produtoId: docId,
        quantidade: 3,
      );

      expect(r.quantidadeTotalAtualizada, 7);
      final snap = await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      expect(snap.data()?['quantidade'], 7);
    });

    test('produto cor-only baixa célula e remove chave zerada no Firestore', () async {
      const docId = 'prod-cor-only';
      await _seedProduto(db, docId: docId, data: {
        'nome': 'Anel Rosa',
        'quantidade': 1,
        'variacoes': {
          'sem-tamanho': {'Rosa': 1},
        },
        'estoquePorTamanho': {'sem-tamanho': 1},
      });

      final r = await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: _lojaId,
        produtoId: docId,
        quantidade: 1,
        cor: 'Rosa',
      );

      expect(r.quantidadeTotalAtualizada, 0);
      final snap = await db
          .collection('lojas')
          .doc(_lojaId)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(docId)
          .get();
      final data = snap.data()!;
      expect(data['quantidade'], 0);
      final vars = data['variacoes'] as Map<String, dynamic>?;
      expect(vars == null || vars.isEmpty, isTrue);
      final est = data['estoquePorTamanho'] as Map<String, dynamic>?;
      expect(est == null || est.isEmpty, isTrue);
    });

    test('produto tamanho+cor baixa combinação correta', () async {
      const docId = 'prod-tam-cor';
      await _seedProduto(db, docId: docId, data: {
        'nome': 'Anel Ajustável',
        'quantidade': 6,
        'variacoes': {
          'P': {'Azul': 2, 'Rosa': 1},
          'M': {'Azul': 3},
        },
        'estoquePorTamanho': {'P': 3, 'M': 3},
      });

      final r = await EstoqueTransactionService.baixarEstoqueTransaction(
        lojaId: _lojaId,
        produtoId: docId,
        quantidade: 1,
        tamanho: 'P',
        cor: 'Azul',
      );

      expect(r.quantidadeTotalAtualizada, 5);
      final vars = r.variacoesAtualizadas!;
      expect(vars['P']['Azul'], 1);
      expect(vars['P']['Rosa'], 1);
      expect(vars['M']['Azul'], 3);
    });

    test('buildEstoqueUpdateDataComDeletes marca FieldValue.delete em cor removida', () {
      final payload = EstoqueTransactionService.buildEstoqueUpdateDataComDeletes(
        novaQuantidadeTotal: 0,
        variacoesAnteriores: {
          'sem-tamanho': {'Rosa': 2},
        },
        variacoesNovas: {},
        estoquePorTamanhoAnterior: {'sem-tamanho': 2},
        estoquePorTamanhoNovo: {},
      );

      expect(payload['variacoes.sem-tamanho'], FieldValue.delete());
      expect(payload['estoquePorTamanho.sem-tamanho'], FieldValue.delete());
    });
  });
}
