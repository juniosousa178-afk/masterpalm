import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_estoque_grade_canonical_guard.dart';

void main() {
  group('Zerar/excluir variação — Grumet 50cm real', () {
    test('merge aceita qtd 0 explícita na grade local', () {
      final merged = produtoFormMergeVariacoesGradeRows([
        {'tamanho': '50cm', 'cor': 'prata', 'qtd': '0'},
      ]);
      expect(merged.variacoes['50cm'], {'prata': 0});
    });

    test('grade canônica com zero não é push incompleta', () {
      expect(
        ProdutoEstoqueGradeCanonicalGuard.gradePushIncompleta(
          variacoes: {'50cm': {'prata': 0}},
          variacoesExtraTipo: {},
          estoquePorTamanho: {},
          tamanhos: ['50cm'],
        ),
        isFalse,
      );
    });

    test('produto qty total 0 com variação 0 é válido', () {
      expect(
        ProdutoEstoqueGradeCanonicalGuard.gradeCoreCompleta(
          variacoes: {'50cm': {'prata': 0}},
          estoquePorTamanho: {},
        ),
        isTrue,
      );
    });
  });
}
