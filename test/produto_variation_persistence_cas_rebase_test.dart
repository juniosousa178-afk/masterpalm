import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_stock_revision.dart';
import 'package:master_palm/core/produto_variation_cas_rebase.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/services/produto_stock_catalog_cadastro_sync.dart';
import 'package:master_palm/services/produto_sync_erro_util.dart';
import 'package:master_palm/services/venda_combo_estoque_expansion.dart';
import 'package:master_palm/models/venda_item.dart';

void main() {
  group('variation identity + CAS rebase', () {
    test('normKey matches backend-style trim/case/space', () {
      expect(ProdutoVariationIdentity.normKey(' 15 '), '15');
      expect(ProdutoVariationIdentity.normKey('Ab  C'), 'ab c');
      expect(
        ProdutoVariationIdentity.keysMatch('15', '15'),
        isTrue,
      );
      expect(
        ProdutoVariationIdentity.keysMatch('015', '15'),
        isFalse,
      );
    });

    test('VARIATION_PRODUCT_CREATE style definition keeps sizes 15/19/20',
        () async {
      final produto = Produto.vazio()
        ..idFirebase = 'p-var'
        ..nome = 'Anel'
        ..quantidade = 6
        ..stockRevision = 0
        ..variacoes = {
          '15': {'sem-cor': 2},
          '19': {'sem-cor': 2},
          '20': {'sem-cor': 2},
        }
        ..estoquePorTamanho = {'15': 2, '19': 2, '20': 2}
        ..tamanhos = ['15', '19', '20'];

      final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
        produto: produto,
        produtoId: 'p-var',
        documentExists: false,
        forcePushFromCadastro: true,
      );
      expect(intent.kind, 'create');
      final vars = intent.definition!['variacoes'] as Map;
      expect(vars.keys.toSet(), {'15', '19', '20'});
    });

    test('PRODUCT_EDIT preserves variation keys after rebuild', () async {
      final produto = Produto.vazio()
        ..idFirebase = 'p-edit'
        ..quantidade = 4
        ..stockRevision = 2
        ..variacoes = {
          '15': {'sem-cor': 2},
          '19': {'sem-cor': 2},
        }
        ..estoquePorTamanho = {'15': 2, '19': 2}
        ..nome = 'Anel editado';

      final baseline = ProdutoFormGradeBaseline.capture(produto);
      produto.nome = 'Anel editado 2';

      final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
        produto: produto,
        produtoId: 'p-edit',
        documentExists: true,
        forcePushFromCadastro: true,
        gradeBaseline: baseline,
      );
      expect(intent.kind, 'replace');
      expect(intent.expectedRevision, 2);
      final vars = intent.definition!['variacoes'] as Map;
      expect(vars.keys.toSet(), {'15', '19'});
    });

    test('ADD_VARIATION keeps existing keys; new key unique', () async {
      final produto = Produto.vazio()
        ..idFirebase = 'p-add'
        ..quantidade = 3
        ..stockRevision = 1
        ..variacoes = {
          '15': {'sem-cor': 1},
          '19': {'sem-cor': 1},
        }
        ..estoquePorTamanho = {'15': 1, '19': 1};
      final baseline = ProdutoFormGradeBaseline.capture(produto);
      produto.variacoes = {
        '15': {'sem-cor': 1},
        '19': {'sem-cor': 1},
        '20': {'sem-cor': 1},
      };
      produto.estoquePorTamanho = {'15': 1, '19': 1, '20': 1};
      produto.quantidade = 3;

      final intent = await ProdutoStockCatalogCadastroSync.buildOrReuseIntent(
        produto: produto,
        produtoId: 'p-add',
        documentExists: true,
        forcePushFromCadastro: true,
        gradeBaseline: baseline,
        remoteStockData: {
          'stockRevision': 3,
          'quantidade': 2,
          'variacoes': {
            '15': {'sem-cor': 1},
            '19': {'sem-cor': 1},
          },
          'estoquePorTamanho': {'15': 1, '19': 1},
        },
        allowRemoteCasRebase: true,
      );

      expect(intent.kind, 'replace');
      expect(intent.expectedRevision, 3);
      final vars = Map<String, dynamic>.from(intent.definition!['variacoes'] as Map);
      expect(vars.keys.toSet(), {'15', '19', '20'});
      // Células não editadas herdam remoto (venda): qty permanece 1.
      expect((vars['15'] as Map)['sem-cor'], 1);
      expect((vars['20'] as Map)['sem-cor'], 1);
    });

    test('REMOVE_VARIATION drops key; remaining identities stable', () async {
      final produto = Produto.vazio()
        ..idFirebase = 'p-rm'
        ..quantidade = 3
        ..stockRevision = 1
        ..variacoes = {
          '15': {'sem-cor': 1},
          '19': {'sem-cor': 1},
          '20': {'sem-cor': 1},
        };
      final baseline = ProdutoFormGradeBaseline.capture(produto);
      produto.variacoes = {
        '15': {'sem-cor': 1},
        '20': {'sem-cor': 1},
      };
      produto.quantidade = 2;

      final def = ProdutoVariationCasRebase.rebaseReplaceDefinition(
        editorDefinition:
            ProdutoStockCatalogCadastroSync.buildDefinition(produto),
        gradeBaseline: baseline,
        remoteData: {
          'stockRevision': 2,
          'quantidade': 3,
          'variacoes': {
            '15': {'sem-cor': 1},
            '19': {'sem-cor': 1},
            '20': {'sem-cor': 1},
          },
        },
      );
      final vars = Map<String, dynamic>.from(def['variacoes'] as Map);
      expect(vars.keys.toSet(), {'15', '20'});
      expect(vars.containsKey('19'), isFalse);
    });

    test('CAS rebase preserves remote qty when editor cell unchanged', () {
      const baseline = ProdutoFormGradeBaseline(
        stockRevision: 1,
        quantidade: 4,
        variacoes: {
          '15': {'sem-cor': 2},
          '19': {'sem-cor': 2},
        },
        estoquePorTamanho: {'15': 2, '19': 2},
      );
      final editorDef = {
        'quantidade': 5,
        'variacoes': {
          '15': {'sem-cor': 2}, // unchanged vs baseline
          '19': {'sem-cor': 2},
          '20': {'sem-cor': 1}, // added
        },
        'estoquePorTamanho': {'15': 2, '19': 2, '20': 1},
      };
      final remote = {
        'stockRevision': 5,
        'quantidade': 3,
        'variacoes': {
          '15': {'sem-cor': 1}, // sale decremented
          '19': {'sem-cor': 2},
        },
        'estoquePorTamanho': {'15': 1, '19': 2},
      };
      final rebased = ProdutoVariationCasRebase.rebaseReplaceDefinition(
        editorDefinition: editorDef,
        gradeBaseline: baseline,
        remoteData: remote,
      );
      final vars = Map<String, dynamic>.from(rebased['variacoes'] as Map);
      expect((vars['15'] as Map)['sem-cor'], 1);
      expect((vars['19'] as Map)['sem-cor'], 2);
      expect((vars['20'] as Map)['sem-cor'], 1);
      expect(ProdutoVariationCasRebase.remoteRevision(remote), 5);
    });

    test('concurrent edit of same cell throws explicit conflict', () {
      const baseline = ProdutoFormGradeBaseline(
        stockRevision: 1,
        quantidade: 2,
        variacoes: {
          '15': {'sem-cor': 2},
        },
      );
      expect(
        () => ProdutoVariationCasRebase.rebaseReplaceDefinition(
          editorDefinition: {
            'quantidade': 5,
            'variacoes': {
              '15': {'sem-cor': 5},
            },
          },
          gradeBaseline: baseline,
          remoteData: {
            'stockRevision': 2,
            'quantidade': 1,
            'variacoes': {
              '15': {'sem-cor': 1},
            },
          },
        ),
        throwsA(isA<ProdutoCasConflictException>()),
      );
    });

    test('aborted maps to human conflict message (not raw aborted)', () {
      final err = FirebaseFunctionsException(
        code: 'aborted',
        message: 'Stock revision conflict',
      );
      final msg = ProdutoSyncErroUtil.sanitizar(err)!;
      expect(msg.toLowerCase().contains('aborted'), isFalse);
      expect(msg.contains('conflito de versão'), isTrue);
      expect(
        ProdutoVariationCasRebase.isStockRevisionConflict(err),
        isTrue,
      );
    });

    test('PDV payload trims size/color/extra', () {
      final produto = Produto.vazio()..idFirebase = 'p1';
      final item = VendaItem(
        produtoNome: 'Anel',
        quantidade: 1,
        precoUnitario: 10,
        tamanho: ' 15 ',
        cor: ' Azul ',
        extraValor: '  ',
      );
      final rows = VendaComboEstoqueExpansion.montarItensParaBackend(
        itens: [item],
        produtos: [produto],
      );
      expect(rows.single['size'], '15');
      expect(rows.single['color'], 'Azul');
      expect(rows.single['extra'], '');
    });

    test('rebuild after conflict clears pending and uses remote revision',
        () async {
      final produto = Produto.vazio()
        ..idFirebase = 'p-cas'
        ..quantidade = 3
        ..stockRevision = 1
        ..variacoes = {
          '15': {'sem-cor': 1},
          '20': {'sem-cor': 2},
        };
      markPendingStockMutation(
        produto,
        operationId: 'old-op',
        baseRevision: 1,
      );
      final baseline = ProdutoFormGradeBaseline(
        stockRevision: 1,
        quantidade: 1,
        variacoes: {
          '15': {'sem-cor': 1},
        },
        estoquePorTamanho: const {'15': 1},
      );
      final intent =
          await ProdutoStockCatalogCadastroSync.rebuildReplaceIntentAfterConflict(
        produto: produto,
        produtoId: 'p-cas',
        remoteData: {
          'stockRevision': 4,
          'quantidade': 1,
          'variacoes': {
            '15': {'sem-cor': 1},
          },
          'estoquePorTamanho': {'15': 1},
        },
        gradeBaseline: baseline,
      );
      expect(intent.kind, 'replace');
      expect(intent.expectedRevision, 4);
      expect(intent.operationId, isNot('old-op'));
      expect(hasPendingStockMutation(produto), isTrue);
      expect(produto.pendingStockOperationId, intent.operationId);
    });

    test('EMPTY optional color uses sem-cor sentinel in cell id', () {
      expect(
        ProdutoVariationIdentity.cellId('15', ''),
        '15|sem-cor',
      );
      expect(
        ProdutoVariationIdentity.canonicalColor(''),
        'sem-cor',
      );
    });
  });
}
