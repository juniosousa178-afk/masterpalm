import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/core/produto_variacao_normalizer.dart';
import 'package:master_palm/models/produto.dart';

Produto _produtoLegadoEstoque({
  Map<String, int>? estoquePorTamanho,
  List<String>? tamanhos,
  Map<String, dynamic>? variacoes,
  Map<String, dynamic>? variacoesExtraTipo,
  Map<String, double>? precoPorTamanho,
}) {
  return Produto(
    nome: 'Anel Aparador Cravejado',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: 12,
    precoUnitario: 50,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: 'nathy_pratas_e_folheados',
    estoquePorTamanho: estoquePorTamanho ?? const {},
    tamanhos: tamanhos ?? const [],
    variacoes: variacoes,
    variacoesExtraTipo: variacoesExtraTipo,
    precoPorTamanho: precoPorTamanho,
  );
}

void main() {
  group('hidratação cadastro — ProdutoVariacaoNormalizer', () {
    test('estoquePorTamanho sem variacoes gera linhas da grade', () {
      final p = _produtoLegadoEstoque(
        estoquePorTamanho: const {
          '14': 2,
          '15': 1,
          '18': 3,
          '20': 2,
          '22': 1,
          '15/16': 3,
        },
      );

      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 6);
      expect(rows.map((r) => r['tamanho']).toSet(), containsAll([
        '14',
        '15',
        '18',
        '20',
        '22',
        '15/16',
      ]));

      final norm = ProdutoVariacaoNormalizer.normalizedFromProduto(p);
      expect(norm.hydratedFromLegacy, isTrue);
      expect(norm.variacoes.keys, containsAll(['14', '15', '18']));
      expect(
        ProdutoVariacaoExtra.somarCelula(
          (norm.variacoes['14'] as Map)['sem-cor'],
        ),
        2,
      );
    });

    test('variacoesExtraTipo completo preserva eixo extra na grade', () {
      final p = _produtoLegadoEstoque(
        variacoes: {
          'M': {
            'Azul': {
              'P': 2,
            },
          },
        },
        variacoesExtraTipo: {
          'M': {
            'Azul': {
              'P': 'Pedra',
            },
          },
        },
        estoquePorTamanho: const {'M': 2},
      );

      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows, isNotEmpty);
      expect(rows.first['tamanho'], 'M');
      expect(rows.first['cor'], 'Azul');
      expect(rows.first['extraValor'], 'P');
      expect(rows.first['extraTipo'], 'Pedra');
    });

    test('variacoes legado (sem extra) aparece na grade', () {
      final p = _produtoLegadoEstoque(
        variacoes: {
          'G': {
            'sem-cor': {ProdutoVariacaoExtra.kSemExtraKey: 4},
          },
        },
        estoquePorTamanho: const {'G': 4},
      );

      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 1);
      expect(rows.first['tamanho'], 'G');
      expect(rows.first['qtd'], '4');
    });

    test('precoPorTamanho não impede hidratação de estoque legado', () {
      final p = _produtoLegadoEstoque(
        estoquePorTamanho: const {'14': 1, '16': 2},
        precoPorTamanho: const {'14': 45.0, '16': 48.0},
      );

      final norm = ProdutoVariacaoNormalizer.normalizedFromProduto(p);
      expect(norm.variacoes.isNotEmpty, isTrue);
      expect(p.precoPorTamanho?['14'], 45.0);
    });

    test('produto simples sem grade permanece simples', () {
      final p = _produtoLegadoEstoque();
      expect(ProdutoVariacaoNormalizer.gradeRowsFromProduto(p), isEmpty);
      expect(
        ProdutoVariacaoNormalizer.hasRepresentacaoVariacao(
          variacoes: p.variacoes,
          estoquePorTamanho: p.estoquePorTamanho,
        ),
        isFalse,
      );
    });

    test('applyToProduto preenche variacoes no Hive a partir do legado', () {
      final p = _produtoLegadoEstoque(
        estoquePorTamanho: const {'14': 2, '15': 1},
      );
      expect(p.variacoes, isNull);

      final hydrated = ProdutoVariacaoNormalizer.applyToProduto(p);
      expect(hydrated, isTrue);
      expect(p.variacoes, isNotNull);
      expect(p.variacoes!['14'], isNotNull);
      expect(p.estoquePorTamanho['14'], 2);
    });

    test('somente tamanhos (sem qtd) ainda gera linhas na grade', () {
      final p = _produtoLegadoEstoque(
        tamanhos: const ['14', '15', '18'],
      );
      final rows = ProdutoVariacaoNormalizer.gradeRowsFromProduto(p);
      expect(rows.length, 3);
      expect(rows.every((r) => r['qtd'] == '0'), isTrue);
    });
  });
}
