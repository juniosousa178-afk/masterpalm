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
  String custo = '',
}) {
  return {
    'tamanho': TextEditingController(text: tamanho),
    'cor': TextEditingController(text: cor),
    'extraTipo': TextEditingController(text: ''),
    'extraValor': TextEditingController(text: ''),
    'qtd': TextEditingController(text: qtd),
    'custo': TextEditingController(text: custo),
  };
}

void _disposeRows(List<Map<String, TextEditingController>> rows) {
  for (final row in rows) {
    for (final c in row.values) {
      c.dispose();
    }
  }
}

Produto _produtoComVariacao({
  required String lojaId,
  required String productId,
}) {
  return Produto(
    nome: 'Camiseta',
    custoReal: 20,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 59.9,
    quantidade: 5,
    precoUnitario: 59.9,
    categoria: 'Roupas',
    dataEntrada: DateTime(2026, 5, 30),
    lojaId: lojaId,
    idFirebase: productId,
    slug: productId,
    custoEditadoNoCadastro: true,
    variacoes: {
      'M': {
        'Azul': {
          ProdutoVariacaoExtra.kSemExtraKey: 5,
          ProdutoVariacaoExtra.kMetaCustoUnitarioKey: 18.0,
        },
      },
    },
    estoquePorTamanho: const {'M': 5},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('edição de variação — persistência', () {
    test('merge da grade reflete qtd, custo e preserva outras células', () {
      final rows = <Map<String, TextEditingController>>[
        _row(tamanho: 'M', cor: 'Azul', qtd: '8', custo: '19,50'),
        _row(tamanho: 'G', cor: 'Preto', qtd: '2'),
      ];

      final merged = produtoFormMergeVariacoesGrade(rows);
      final variacoes = merged.variacoes;

      final azul = (variacoes['M'] as Map<String, dynamic>)['Azul'];
      expect(ProdutoVariacaoExtra.somarCelula(azul), 8);
      expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(azul), 19.5);

      final preto = (variacoes['G'] as Map<String, dynamic>)['Preto'];
      expect(ProdutoVariacaoExtra.somarCelula(preto), 2);

      _disposeRows(rows);
    });

    test('Hive roundtrip mantém variações editadas', () async {
      final hiveDir =
          Directory.systemTemp.createTempSync('produto_variacao_hive_');
      Hive.init(hiveDir.path);
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ProdutoAdapter());
      }

      try {
        final box = await Hive.openBox<Produto>('produtos_variacao_edit');
        final original = _produtoComVariacao(
          lojaId: 'loja-teste',
          productId: 'prod-var-1',
        );

        final rows = <Map<String, TextEditingController>>[
          _row(tamanho: 'M', cor: 'Azul', qtd: '12', custo: '21,00'),
        ];
        final merged = produtoFormMergeVariacoesGrade(rows);
        original.variacoes = merged.variacoes;
        original.estoquePorTamanho = const {'M': 12};
        original.quantidade = 12;
        original.updatedAt = DateTime.now();

        final key = await box.add(original);
        final loaded = box.get(key);

        expect(loaded, isNotNull);
        final cell = (loaded!.variacoes!['M'] as Map<String, dynamic>)['Azul'];
        expect(ProdutoVariacaoExtra.somarCelula(cell), 12);
        expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(cell), 21.0);
        expect(loaded.quantidade, 12);

        await box.close();
        _disposeRows(rows);
      } finally {
        Hive.close();
        if (hiveDir.existsSync()) {
          hiveDir.deleteSync(recursive: true);
        }
      }
    });

    test('sync Firestore grava variações editadas no doc remoto', () async {
      SharedPreferences.setMockInitialValues({});
      final firestore = FakeFirebaseFirestore();
      ProdutosFirestoreService.debugFirestoreOverride = firestore;

      const lojaId = 'loja-teste';
      const productId = 'prod-var-sync';

      try {
        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .set({
          'id': productId,
          'slug': productId,
          'nome': 'Camiseta',
          'variacoes': {
            'M': {
              'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 5},
            },
          },
        });

        final produto = _produtoComVariacao(
          lojaId: lojaId,
          productId: productId,
        );
        final rows = <Map<String, TextEditingController>>[
          _row(tamanho: 'M', cor: 'Azul', qtd: '9', custo: '17,00'),
        ];
        final merged = produtoFormMergeVariacoesGrade(rows);
        produto.variacoes = merged.variacoes;
        produto.estoquePorTamanho = const {'M': 9};
        produto.quantidade = 9;

        final status = await ProdutosFirestoreService.syncProdutoComStatus(
          produto,
          lojaId: lojaId,
          bumpHiveTimestamp: false,
          forcePushFromCadastro: true,
          enqueueOnFailure: false,
        );

        expect(status, ProdutoSyncRemotoStatus.confirmado);

        final snap = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .get();
        final remoto = snap.data()?['variacoes'] as Map<String, dynamic>?;
        expect(remoto, isNotNull);
        final cell = (remoto!['M'] as Map<String, dynamic>)['Azul'];
        expect(ProdutoVariacaoExtra.somarCelula(cell), 9);
        expect(ProdutoVariacaoExtra.custoUnitarioNaCelula(cell), 17.0);

        _disposeRows(rows);
      } finally {
        ProdutosFirestoreService.debugFirestoreOverride = null;
      }
    });

    test(
        'pull ignora variacoes remotas vazias quando cadastro manual tem grade',
        () {
      final local = _produtoComVariacao(
        lojaId: 'loja-teste',
        productId: 'prod-var-pull',
      );

      expect(
        ProdutosFirestoreService.shouldIgnoreEmptyRemoteVariacoesOnPull(
          local: local,
          remoteVariacoes: null,
        ),
        isTrue,
      );
      expect(
        ProdutosFirestoreService.shouldIgnoreEmptyRemoteVariacoesOnPull(
          local: local,
          remoteVariacoes: <String, dynamic>{},
        ),
        isTrue,
      );
      expect(
        ProdutosFirestoreService.shouldIgnoreEmptyRemoteVariacoesOnPull(
          local: local,
          remoteVariacoes: {
            'M': {
              'Azul': {ProdutoVariacaoExtra.kSemExtraKey: 3},
            },
          },
        ),
        isFalse,
      );
    });
  });
}
