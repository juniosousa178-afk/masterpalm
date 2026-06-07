import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_variacao_extra.dart';
import 'package:master_palm/models/produto.dart';
import 'package:master_palm/screens/produto_form_screen.dart';

Produto _produtoBase({
  Map<String, int>? estoquePorTamanho,
  Map<String, dynamic>? variacoes,
  Map<String, dynamic>? variacoesExtraTipo,
  List<String>? tamanhos,
  int quantidade = 5,
}) {
  return Produto(
    nome: 'Anel Teste',
    custoReal: 10,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 50,
    quantidade: quantidade,
    precoUnitario: 50,
    categoria: 'Aneis',
    dataEntrada: DateTime(2026, 6, 7),
    lojaId: 'loja-grade',
    idFirebase: 'prod-grade-1',
    slug: 'prod-grade-1',
    estoquePorTamanho: estoquePorTamanho ?? const {},
    variacoes: variacoes,
    variacoesExtraTipo: variacoesExtraTipo,
    tamanhos: tamanhos ?? const [],
    precoPorTamanho: const {'19': 55.0},
  );
}

void main() {
  group('lista vs cadastro — consistência de grade', () {
    test('lista indica variação com estoquePorTamanho sem variacoes', () {
      final p = _produtoBase(estoquePorTamanho: const {'19': 1});
      expect(p.usaVariacoes, isFalse);
      expect(produtoListaIndicaVariacao(p), isTrue);
    });

    test('estoquePorTamanho {19:1} hidrata linha tamanho 19 qtd 1', () {
      final p = _produtoBase(estoquePorTamanho: const {'19': 1});
      final h = produtoFormHydrateGradeRows(p);
      expect(h.source, ProdutoFormGradeHydrationSource.estoquePorTamanho);
      expect(h.rows.length, 1);
      expect(h.rows.first['tamanho'], '19');
      expect(h.rows.first['cor'], '');
      expect(h.rows.first['qtd'], '1');
    });

    test('estoquePorTamanho com cor ausente mantém cor vazia', () {
      final rows = produtoFormBuildGradeRowsFromEstoquePorTamanho({'M': 2});
      expect(rows.single['cor'], '');
      expect(rows.single['qtd'], '2');
    });

    test('chave 19|Prata mostra tamanho 19 cor Prata', () {
      final rows =
          produtoFormBuildGradeRowsFromEstoquePorTamanho({'19|Prata': 3});
      expect(rows.single['tamanho'], '19');
      expect(rows.single['cor'], 'Prata');
      expect(rows.single['qtd'], '3');
    });

    test('chave 19|Prata|Letra|A preserva extra', () {
      final parsed = produtoFormParseEstoquePorTamanhoKey('19|Prata|Letra|A');
      expect(parsed.tamanho, '19');
      expect(parsed.cor, 'Prata');
      expect(parsed.extraTipo, 'Letra');
      expect(parsed.extraValor, 'A');

      final rows = produtoFormBuildGradeRowsFromEstoquePorTamanho({
        '19|Prata|Letra|A': 1,
      });
      expect(rows.single['extraTipo'], 'Letra');
      expect(rows.single['extraValor'], 'A');
    });

    test('variacoes preenchidas têm prioridade sobre estoquePorTamanho', () {
      final p = _produtoBase(
        estoquePorTamanho: const {'P': 9},
        variacoes: {
          'M': {'sem-cor': 2},
        },
      );
      final h = produtoFormHydrateGradeRows(p);
      expect(h.source, ProdutoFormGradeHydrationSource.variacoes);
      expect(h.rows.single['tamanho'], 'M');
      expect(h.rows.single['qtd'], '2');
    });

    test('somente tamanhos: linhas visuais sem quantidade inventada', () {
      final p = _produtoBase(tamanhos: const ['P', 'M']);
      final h = produtoFormHydrateGradeRows(p);
      expect(h.source, ProdutoFormGradeHydrationSource.tamanhosSomente);
      expect(h.rows.length, 2);
      expect(h.rows.every((r) => (r['qtd'] ?? '').isEmpty), isTrue);
    });

    test('produto simples permanece sem grade hidratada', () {
      final p = _produtoBase(quantidade: 4);
      final h = produtoFormHydrateGradeRows(p);
      expect(h.source, ProdutoFormGradeHydrationSource.nenhuma);
      expect(h.rows, isEmpty);
      expect(produtoListaIndicaVariacao(p), isFalse);
    });

    test('salvar grade reidratada gera variacoes coerentes', () {
      final rows = produtoFormBuildGradeRowsFromEstoquePorTamanho({'19': 1});
      final controllers = <Map<String, TextEditingController>>[];
      for (final r in rows) {
        controllers.add({
          'tamanho': TextEditingController(text: r['tamanho']),
          'cor': TextEditingController(text: r['cor']),
          'extraTipo': TextEditingController(text: r['extraTipo']),
          'extraValor': TextEditingController(text: r['extraValor']),
          'qtd': TextEditingController(text: r['qtd']),
          'custo': TextEditingController(text: r['custo']),
        });
      }

      final merged = produtoFormMergeVariacoesGrade(controllers);
      expect(merged.variacoes.containsKey('19'), isTrue);
      expect(
        ProdutoVariacaoExtra.somarCelula(merged.variacoes['19']!['sem-cor']),
        1,
      );
      for (final c in controllers) {
        for (final ctrl in c.values) {
          ctrl.dispose();
        }
      }
    });

    test('precoPorTamanho do produto não é alterado pela hidratação', () {
      final p = _produtoBase(estoquePorTamanho: const {'19': 1});
      final antes = Map<String, double>.from(p.precoPorTamanho!);
      produtoFormHydrateGradeRows(p);
      expect(p.precoPorTamanho, equals(antes));
    });
  });
}
