import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/core/produto_variacao_normalizer.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/produto_form_screen.dart';

Map<String, TextEditingController> _emptyRow() => {
      'tamanho': TextEditingController(),
      'cor': TextEditingController(),
      'extraTipo': TextEditingController(),
      'extraValor': TextEditingController(),
      'qtd': TextEditingController(),
      'custo': TextEditingController(),
    };

/// Simula o ramo de salvamento quando a grade visual está vazia mas o produto
/// original tinha estoque legado (preservação no form).
({
  Map<String, dynamic> variacoes,
  Map<String, dynamic>? variacoesExtraTipo,
  Map<String, int> estoquePorTamanho,
}) simulatePreserveOnSave({
  required Produto original,
  required List<Map<String, TextEditingController>> gradeControllers,
}) {
  final merged = produtoFormMergeVariacoesGrade(gradeControllers);
  var variacoesMap = merged.variacoes;
  var variacoesExtraTipo = merged.variacoesExtraTipo;
  if (variacoesMap.isEmpty) {
    final norm = ProdutoVariacaoNormalizer.normalizedFromProduto(original);
    if (norm.variacoes.isNotEmpty) {
      variacoesMap = norm.variacoes;
      variacoesExtraTipo = norm.variacoesExtraTipo;
    }
  }

  final estoqueMapa = <String, int>{};
  for (final tamanho in variacoesMap.keys) {
    if (tamanho == 'sem-tamanho') continue;
    final mapaInterno = variacoesMap[tamanho] as Map<String, dynamic>;
    var total = 0;
    for (final v in mapaInterno.values) {
      total += ProdutoVariacaoExtra.somarCelula(v);
    }
    estoqueMapa[tamanho] = total;
  }

  return (
    variacoes: variacoesMap,
    variacoesExtraTipo: variacoesExtraTipo,
    estoquePorTamanho: estoqueMapa,
  );
}

void main() {
  group('preservação ao salvar — grade vazia + legado', () {
    test('não zera estoquePorTamanho quando usuário não alterou variações', () {
      final original = Produto(
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
        lojaId: 'loja',
        estoquePorTamanho: const {'14': 2, '15': 1, '18': 3},
      );

      final rows = [_emptyRow()];
      final out = simulatePreserveOnSave(
        original: original,
        gradeControllers: rows,
      );

      expect(out.variacoes.isNotEmpty, isTrue);
      expect(out.estoquePorTamanho['14'], 2);
      expect(out.estoquePorTamanho['15'], 1);
      expect(out.estoquePorTamanho['18'], 3);

      for (final row in rows) {
        for (final c in row.values) {
          c.dispose();
        }
      }
    });

    test('grade preenchida pelo usuário tem prioridade sobre legado', () {
      final original = Produto(
        nome: 'Anel',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 50,
        quantidade: 5,
        precoUnitario: 50,
        categoria: 'Aneis',
        dataEntrada: DateTime(2026, 1, 1),
        lojaId: 'loja',
        estoquePorTamanho: const {'14': 5},
      );

      final rows = [
        {
          'tamanho': TextEditingController(text: '16'),
          'cor': TextEditingController(),
          'extraTipo': TextEditingController(),
          'extraValor': TextEditingController(),
          'qtd': TextEditingController(text: '3'),
          'custo': TextEditingController(),
        },
      ];

      final out = simulatePreserveOnSave(
        original: original,
        gradeControllers: rows,
      );

      expect(out.variacoes.containsKey('16'), isTrue);
      expect(out.variacoes.containsKey('14'), isFalse);

      for (final row in rows) {
        for (final c in row.values) {
          c.dispose();
        }
      }
    });

    test('produto simples com grade vazia continua sem variacoes', () {
      final original = Produto(
        nome: 'Colar',
        custoReal: 5,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 30,
        quantidade: 2,
        precoUnitario: 30,
        categoria: 'Colares',
        dataEntrada: DateTime(2026, 1, 1),
        lojaId: 'loja',
      );

      final rows = [_emptyRow()];
      final out = simulatePreserveOnSave(
        original: original,
        gradeControllers: rows,
      );

      expect(out.variacoes, isEmpty);
      expect(out.estoquePorTamanho, isEmpty);

      for (final row in rows) {
        for (final c in row.values) {
          c.dispose();
        }
      }
    });
  });
}
