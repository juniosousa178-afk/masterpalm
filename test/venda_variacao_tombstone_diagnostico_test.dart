import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/models/venda_item.dart';
import 'package:master_palm/screens/produto_form_screen.dart';
import 'package:master_palm/services/estoque_transaction_service.dart';
import 'package:master_palm/services/firestore_paths.dart';
import 'package:master_palm/services/produto_exclusao_tombstone_service.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cenário reportado: Solitário Detalhe Lateral — Tam 18, Cor sem-cor, Qtd 1.
Produto _produtoSolitarioTam18({
  required String lojaId,
  required String productId,
}) {
  return Produto(
    nome: 'Solitário Detalhe Lateral',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 59.9,
    quantidade: 1,
    precoUnitario: 59.9,
    categoria: 'Anéis',
    dataEntrada: DateTime(2026, 5, 30),
    lojaId: lojaId,
    idFirebase: productId,
    slug: productId,
    custoEditadoNoCadastro: true,
    variacoes: {
      '18': {
        'sem-cor': {
          ProdutoVariacaoExtra.kSemExtraKey: 1,
        },
      },
    },
    estoquePorTamanho: const {'18': 1},
    precoPorTamanho: const {'18': 59.9},
  );
}

Future<void> _seedEstoqueAtivoTam18(
  FakeFirebaseFirestore firestore, {
  required String lojaId,
  required String productId,
}) {
  return firestore
      .collection('lojas')
      .doc(lojaId)
      .collection('estoque_produtos')
      .doc(productId)
      .set({
    'nome': 'Solitário Detalhe Lateral',
    'quantidade': 1,
    'variacoes': {
      '18': {'sem-cor': 1},
    },
    'estoquePorTamanho': {'18': 1},
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('venda com variação — diagnóstico tombstone', () {
    const lojaId = 'nathy-pratas-e-folheados';
    const productId = 'solitario-detalhe-lateral';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
    });

    tearDown(() {
      ProdutoExclusaoTombstoneService.resetCacheForTests();
      EstoqueTransactionService.debugFirestoreOverride = null;
    });

    test('chaves V:: e T:: para tamanho 18 + sem-cor batem com UI da venda', () {
      const tam = '18';
      const cor = 'sem-cor';

      final vKey = ProdutoExclusaoTombstoneService.vKeyCelula(tam, cor);
      final tKey = ProdutoExclusaoTombstoneService.tKeySoloTamanho(tam);

      final produto = _produtoSolitarioTam18(lojaId: lojaId, productId: productId);
      final chavesV = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes(
        produto.variacoes,
      );
      final chavesT = ProdutoExclusaoTombstoneService
          .chavesSoloTamanhoDeEstoquePorTamanho(produto.estoquePorTamanho);

      expect(chavesV, contains(vKey));
      expect(chavesT, contains(tKey));
      expect(produto.obterEstoqueVariacao(tam, cor), 1);
    });

    test('sem-cor na UI da venda vs cor vazia gera chaves V:: diferentes', () {
      final comSemCor =
          ProdutoExclusaoTombstoneService.vKeyCelula('18', 'sem-cor');
      final comVazio = ProdutoExclusaoTombstoneService.vKeyCelula('18', '');

      expect(comSemCor, isNot(comVazio));
    });

    test(
      'normalizarCorParaChecagem: cor vazia com mapa sem-cor resolve para sem-cor',
      () {
        expect(
          ProdutoExclusaoTombstoneService.normalizarCorParaChecagem(
            tamanho: '18',
            cor: '',
            variacoes: {
              '18': {'sem-cor': 1},
            },
          ),
          'sem-cor',
        );
      },
    );

    test(
      'merge da grade normaliza cor vazia para sem-cor — mesma chave V:: que o cadastro',
      () {
        final rows = [
          {
            'tamanho': '18',
            'cor': '',
            'extraTipo': '',
            'extraValor': '',
            'qtd': '1',
            'custo': '',
          },
        ].map((m) {
          return {
            'tamanho': TextEditingController(text: m['tamanho']),
            'cor': TextEditingController(text: m['cor']),
            'extraTipo': TextEditingController(text: m['extraTipo']),
            'extraValor': TextEditingController(text: m['extraValor']),
            'qtd': TextEditingController(text: m['qtd']),
            'custo': TextEditingController(text: m['custo']),
          };
        }).toList();

        final merged = produtoFormMergeVariacoesGrade(rows);
        final chaves = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes(
          merged.variacoes,
        );

        expect(
          chaves,
          contains(ProdutoExclusaoTombstoneService.vKeyCelula('18', 'sem-cor')),
        );

        for (final row in rows) {
          for (final c in row.values) {
            c.dispose();
          }
        }
      },
    );

    test(
      'edição só de qtd/custo não altera chaves V:: — não deveria tombstonear a célula ativa',
      () {
        final baseline = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes({
          '18': {
            'sem-cor': 1,
          },
        });

        final merged = produtoFormMergeVariacoesGrade([
          {
            'tamanho': TextEditingController(text: '18'),
            'cor': TextEditingController(text: ''),
            'extraTipo': TextEditingController(text: ''),
            'extraValor': TextEditingController(text: ''),
            'qtd': TextEditingController(text: '2'),
            'custo': TextEditingController(text: '12,00'),
          },
        ]);
        final novo = ProdutoExclusaoTombstoneService.chavesCelulaDeVariacoes(
          merged.variacoes,
        );

        expect(baseline.difference(novo), isEmpty);
        expect(novo.difference(baseline), isEmpty);
      },
    );

    test(
      'estoquePorTamanho legado com tamanho extra tombstoneia só T:: removido, não T::18 ativo',
      () {
        final baselineT = ProdutoExclusaoTombstoneService
            .chavesSoloTamanhoDeEstoquePorTamanho({
          '16': 0,
          '18': 1,
        });
        final estoqueMapaAposSave = {'18': 2};
        final novoT = ProdutoExclusaoTombstoneService
            .chavesSoloTamanhoDeEstoquePorTamanho(estoqueMapaAposSave);
        final remT = baselineT.difference(novoT);

        expect(
          remT,
          contains(ProdutoExclusaoTombstoneService.tKeySoloTamanho('16')),
        );
        expect(
          remT,
          isNot(contains(ProdutoExclusaoTombstoneService.tKeySoloTamanho('18'))),
        );
      },
    );

    test(
      'T::18 tombstonado NÃO bloqueia venda quando variacao 18/sem-cor ativa no remoto',
      () async {
        final firestore = FakeFirebaseFirestore();
        ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
        EstoqueTransactionService.debugFirestoreOverride = firestore;

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(productId)
            .set({
          'p': false,
          'v': {
            ProdutoExclusaoTombstoneService.tKeySoloTamanho('18'): true,
          },
        });

        await _seedEstoqueAtivoTam18(
          firestore,
          lojaId: lojaId,
          productId: productId,
        );

        final bloqueada =
            await ProdutoExclusaoTombstoneService.isVendaBloqueadaParaCelula(
          lojaId: lojaId,
          estoqueDocId: productId,
          tamanho: '18',
          cor: 'sem-cor',
        );

        expect(bloqueada, isFalse);

        final produto =
            _produtoSolitarioTam18(lojaId: lojaId, productId: productId);
        final txItems = VendaComboEstoqueExpansion.montarTxItemsParaBaixaEstoque(
          itensParaEstoque: [
            VendaItem(
              produtoNome: produto.nome,
              precoUnitario: 59.9,
              quantidade: 1,
              tamanho: '18',
              cor: 'sem-cor',
            ),
          ],
          produtosEncontrados: [produto],
        );

        final result =
            await EstoqueTransactionService.baixarEstoqueTransactionBatch(
          lojaId: lojaId,
          itens: txItems,
        );
        expect(result, hasLength(1));
        expect(result.first.quantidadeDebitada, 1);
      },
    );

    test(
      'V::18/sem-cor tombstonado com célula ativa no remoto não bloqueia venda',
      () async {
        final firestore = FakeFirebaseFirestore();
        ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(productId)
            .set({
          'p': false,
          'v': {
            ProdutoExclusaoTombstoneService.vKeyCelula('18', 'sem-cor'): true,
          },
        });

        await _seedEstoqueAtivoTam18(
          firestore,
          lojaId: lojaId,
          productId: productId,
        );

        final bloqueada =
            await ProdutoExclusaoTombstoneService.isVendaBloqueadaParaCelula(
          lojaId: lojaId,
          estoqueDocId: productId,
          tamanho: '18',
          cor: 'sem-cor',
        );

        expect(bloqueada, isFalse);
      },
    );

    test(
      'V::18/sem-cor tombstonado sem célula no remoto continua bloqueando venda',
      () async {
        final firestore = FakeFirebaseFirestore();
        ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;
        EstoqueTransactionService.debugFirestoreOverride = firestore;

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(productId)
            .set({
          'p': false,
          'v': {
            ProdutoExclusaoTombstoneService.vKeyCelula('18', 'sem-cor'): true,
          },
        });

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection('estoque_produtos')
            .doc(productId)
            .set({
          'nome': 'Solitário Detalhe Lateral',
          'quantidade': 0,
          'variacoes': {},
        });

        final bloqueada =
            await ProdutoExclusaoTombstoneService.isVendaBloqueadaParaCelula(
          lojaId: lojaId,
          estoqueDocId: productId,
          tamanho: '18',
          cor: 'sem-cor',
        );

        expect(bloqueada, isTrue);
      },
    );

    test(
      'liberarTombstonesVariacoesAtivas remove T:: e V:: obsoletos ao re-salvar célula ativa',
      () async {
        final firestore = FakeFirebaseFirestore();
        ProdutoExclusaoTombstoneService.debugFirestoreOverride = firestore;

        final vKey =
            ProdutoExclusaoTombstoneService.vKeyCelula('18', 'sem-cor');
        final tKey = ProdutoExclusaoTombstoneService.tKeySoloTamanho('18');

        await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(productId)
            .set({
          'p': false,
          'v': {vKey: true, tKey: true},
        });

        await ProdutoExclusaoTombstoneService.ensureHydratedForLoja(lojaId);

        await ProdutoExclusaoTombstoneService.liberarTombstonesVariacoesAtivas(
          lojaId: lojaId,
          estoqueDocId: productId,
          variacoesMap: {
            '18': {'sem-cor': 2},
          },
          estoquePorTamanho: const {'18': 2},
        );

        expect(
          ProdutoExclusaoTombstoneService.isVarChaveBloqueadaSinc(
            lojaId,
            productId,
            vKey,
          ),
          isFalse,
        );
        expect(
          ProdutoExclusaoTombstoneService.isVarChaveBloqueadaSinc(
            lojaId,
            productId,
            tKey,
          ),
          isFalse,
        );

        final tombDoc = await firestore
            .collection('lojas')
            .doc(lojaId)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(productId)
            .get();
        final vMap = tombDoc.data()?['v'];
        if (vMap is Map) {
          expect(vMap.containsKey(vKey), isFalse);
          expect(vMap.containsKey(tKey), isFalse);
        } else {
          expect(vMap, isNull);
        }
      },
    );
  });
}
