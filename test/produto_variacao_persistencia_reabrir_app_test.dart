import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/produto_form_screen.dart';
import 'package:master_palm/services/produtos_firestore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, TextEditingController> _row({
  required String tamanho,
  required String cor,
  required String qtd,
}) {
  return {
    'tamanho': TextEditingController(text: tamanho),
    'cor': TextEditingController(text: cor),
    'extraTipo': TextEditingController(text: ''),
    'extraValor': TextEditingController(text: ''),
    'qtd': TextEditingController(text: qtd),
    'custo': TextEditingController(text: ''),
  };
}

void _disposeRows(List<Map<String, TextEditingController>> rows) {
  for (final row in rows) {
    for (final c in row.values) {
      c.dispose();
    }
  }
}

Produto _produtoGradeManual({
  required String lojaId,
  required String productId,
}) {
  return Produto(
    nome: 'Conjunto Teste',
    custoReal: 30,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 89.9,
    quantidade: 6,
    precoUnitario: 89.9,
    categoria: 'Joias',
    dataEntrada: DateTime(2026, 6, 5),
    lojaId: lojaId,
    idFirebase: productId,
    slug: productId,
    custoEditadoNoCadastro: true,
    tamanhos: const ['P', 'M'],
    estoquePorTamanho: const {'P': 2, 'M': 4},
    variacoes: {
      'P': {
        'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 2},
      },
      'M': {
        'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 4},
      },
    },
    updatedAt: DateTime(2026, 6, 5, 14, 0),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('variação — persistência ao reabrir/sync', () {
    test('grade manual salva no Hive com todos os campos', () async {
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_var_reabrir_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      try {
        final box = await Hive.openBox<Produto>('produtos_var_reabrir');
        final p = _produtoGradeManual(
          lojaId: 'loja-teste',
          productId: 'conjunto-var-1',
        );
        final key = await box.add(p);
        final loaded = box.get(key);
        expect(loaded, isNotNull);
        expect(loaded!.variacoes, isNotNull);
        expect(loaded.estoquePorTamanho, {'P': 2, 'M': 4});
        expect(loaded.tamanhos, ['P', 'M']);
        expect(loaded.quantidade, 6);
        await box.close();
      } finally {
        Hive.close();
        if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
      }
    });

    test('payload Firestore inclui variacoes, estoquePorTamanho e tamanhos',
        () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      const lojaId = 'loja-teste';
      const productId = 'conjunto-var-sync';

      try {
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .set({'id': productId, 'slug': productId, 'nome': 'Conjunto'});

        final produto = _produtoGradeManual(
          lojaId: lojaId,
          productId: productId,
        );

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          produto,
          lojaId: lojaId,
          bumpHiveTimestamp: false,
          enqueueOnFailure: false,
        );
        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .get();
        final data = snap.data()!;
        expect(data['variacoes'], isNotNull);
        expect(data['estoquePorTamanho'], {'P': 2, 'M': 4});
        expect(data['tamanhos'], ['P', 'M']);
        expect(data['quantidade'], 6);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test('pull preserva grade local quando remoto vem vazio/stale', () {
      final local = _produtoGradeManual(
        lojaId: 'loja-teste',
        productId: 'conjunto-var-pull',
      );

      ProdutosFirestoreService.applyRemoteVariationFieldsToExistingOnPull(
        local: local,
        data: {
          'variacoes': <String, dynamic>{},
          'estoquePorTamanho': <String, dynamic>{},
          'tamanhos': <String>[],
        },
      );

      expect(local.variacoes, isNotNull);
      expect(local.estoquePorTamanho, {'P': 2, 'M': 4});
      expect(local.tamanhos, ['P', 'M']);
    });

    test('edição só de nome não apaga variacoes no merge da grade', () {
      final rows = <Map<String, TextEditingController>>[
        _row(tamanho: 'P', cor: '', qtd: '2'),
        _row(tamanho: 'M', cor: '', qtd: '4'),
      ];
      final merged = produtoFormMergeVariacoesGrade(rows);
      expect(merged.variacoes.keys, containsAll(['P', 'M']));
      var soma = 0;
      for (final t in merged.variacoes.keys) {
        final m = merged.variacoes[t] as Map<String, dynamic>;
        for (final v in m.values) {
          soma += ProdutoVariacaoExtra.somarCelula(v);
        }
      }
      expect(soma, 6);
      _disposeRows(rows);
    });

    test('produto simples sem grade continua sem variacoes', () {
      final simples = Produto(
        nome: 'Simples',
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 3,
        precoUnitario: 10,
        categoria: 'Geral',
        dataEntrada: DateTime(2026, 6, 5),
        lojaId: 'loja-teste',
      );

      ProdutosFirestoreService.applyRemoteVariationFieldsToExistingOnPull(
        local: simples,
        data: {
          'variacoes': null,
          'estoquePorTamanho': null,
          'tamanhos': <String>[],
        },
      );

      expect(simples.variacoes, isNull);
      expect(simples.estoquePorTamanho, isEmpty);
    });
  });
}
