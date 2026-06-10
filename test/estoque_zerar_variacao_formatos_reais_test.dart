import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_estoque_grade_canonical_guard.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/produto_form_screen.dart';

void main() {
  group('Zerar variação — formatos reais via merge da UI', () {
    test('zero explícito tamanho+cor entra no push (qtd=0)', () {
      final merged = produtoFormMergeVariacoesGradeRows([
        {
          'tamanho': '45cm',
          'cor': 'sem-cor',
          'qtd': '0',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
        {
          'tamanho': '60cm',
          'cor': 'sem-cor',
          'qtd': '2',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
      ]);

      expect(merged.variacoes['45cm'], isNotNull);
      expect(merged.variacoes['45cm']['sem-cor'], 0);
      expect(merged.variacoes['60cm']['sem-cor'], 2);
    });

    test('zerar só cor persiste 0 e mantém outras cores do tamanho', () {
      final baseline = ProdutoFormGradeBaseline.capture(
        Produto(
          nome: 'Anel',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 10,
          quantidade: 5,
          precoUnitario: 10,
          categoria: 'X',
          dataEntrada: DateTime(2026, 6, 9),
          lojaId: 'loja-z',
          variacoes: {
            '18': {'Dourado': 3, 'Prata': 2},
          },
        ),
      );

      final merged = produtoFormMergeVariacoesGradeRows([
        {
          'tamanho': '18',
          'cor': 'Prata',
          'qtd': '0',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
        {
          'tamanho': '18',
          'cor': 'Dourado',
          'qtd': '3',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
      ]);

      final result = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: 'loja-z',
        produtoId: 'p1',
        variacoesPush: merged.variacoes,
        variacoesExtraPush: {},
        estoquePorTamPush: const {'18': 3},
        tamanhosPush: const ['18'],
        quantidade: 3,
        baseline: baseline,
        existingEstoqueData: {
          'variacoes': {
            '18': {'Dourado': 3, 'Prata': 2},
          },
        },
      );

      final mapa = result.variacoes['18'] as Map;
      expect(mapa['Prata'], 0);
      expect(mapa['Dourado'], 3);
      expect(mapa.containsKey('Prata'), isTrue);
    });

    test('zerar só tamanho (sem-cor única) persiste 0', () {
      final merged = produtoFormMergeVariacoesGradeRows([
        {
          'tamanho': 'P',
          'cor': '',
          'qtd': '0',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
      ]);

      expect(merged.variacoes['P']['sem-cor'], 0);
    });

    test('cor-only com zero explícito persiste em sem-tamanho', () {
      final merged = produtoFormMergeVariacoesGradeRows([
        {
          'tamanho': '',
          'cor': 'Rosa',
          'qtd': '0',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
        {
          'tamanho': '',
          'cor': 'Azul',
          'qtd': '1',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
      ]);

      expect(merged.variacoes['sem-tamanho']['Rosa'], 0);
      expect(merged.variacoes['sem-tamanho']['Azul'], 1);
    });

    test('campo ausente (qtd vazia) não entra no push — remoto preservado no tamanho', () {
      final base = {
        'P': {'Azul': 2, 'Rosa': 5},
      };
      final push = produtoFormMergeVariacoesGradeRows([
        {
          'tamanho': 'P',
          'cor': 'Azul',
          'qtd': '1',
          'extraTipo': '',
          'extraValor': '',
          'custo': '',
        },
      ]).variacoes;

      final merged = ProdutoEstoqueGradeCanonicalGuard.mesclarVariacoesComPrioridadePush(
        base: base,
        push: push,
      );

      expect(merged['P'], {'Azul': 1});
      expect(merged['P'], isNot(contains('Rosa')));
    });

    test('produtoFormMergeVariacoesGrade (controllers) inclui zero explícito', () {
      final merged = produtoFormMergeVariacoesGrade([
        {
          'tamanho': TextEditingController(text: 'M'),
          'cor': TextEditingController(text: ''),
          'qtd': TextEditingController(text: '0'),
          'extraTipo': TextEditingController(),
          'extraValor': TextEditingController(),
          'custo': TextEditingController(),
        },
      ]);

      expect(merged.variacoes['M']['sem-cor'], 0);
    });
  });
}
