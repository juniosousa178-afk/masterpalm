import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/core/produto_variation_stock_consistency.dart';
import 'package:master_palm/models/produto.dart';

Produto _p({
  Map<String, dynamic>? variacoes,
  Map<String, int> ept = const {},
  int quantidade = 0,
}) {
  return Produto(
    nome: 'Fixture',
    custoReal: 1,
    frete: 0,
    gastosFixos: 0,
    gastosVariaveis: 0,
    precoSugerido: 0,
    precoFinal: 10,
    quantidade: quantidade,
    precoUnitario: 10,
    categoria: 'Test',
    dataEntrada: DateTime(2026, 1, 1),
    lojaId: 'loja-test',
    idFirebase: 'loja-test-fixture',
    slug: 'loja-test-fixture',
    variacoes: variacoes,
    estoquePorTamanho: ept,
    tamanhos: ept.keys.toList(),
  );
}

void main() {
  group('authoritative qty rehydration — consistency', () {
    test('remote valid: variation qty positive + matching map → consistent', () {
      final p = _p(
        variacoes: {
          '18': {'sem-cor': 2},
        },
        ept: const {'18': 2},
        quantidade: 2,
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.state, ProdutoVariationStockConsistencyState.consistent);
      expect(c.allowResurrectFromEstoquePorTamanho, isFalse);
      expect(c.blocksSilentZeroSave, isFalse);
      expect(c.blocksPdvSale, isFalse);

      final h = produtoFormHydrateGradeRows(p);
      expect(h.source, ProdutoFormGradeHydrationSource.variacoes);
      expect(h.rows.single['qtd'], '2');
      expect(h.consistency?.state, ProdutoVariationStockConsistencyState.consistent);
    });

    test('legitimate zero preserved when both representations agree', () {
      final p = _p(
        variacoes: {
          '18': {'sem-cor': 0},
        },
        ept: const {'18': 0},
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.state, ProdutoVariationStockConsistencyState.consistent);
      expect(c.isOrdinaryTrustedZero, isTrue);
      expect(c.blocksPdvSale, isFalse);

      final h = produtoFormHydrateGradeRows(p);
      expect(h.rows.single['qtd'], '0');
    });

    test('stale local ept must NOT resurrect variation qty', () {
      // LOCAL: var=0 ept=1 — remote all-zero would arrive as ept=0 after sync.
      // Evaluating the stale local snapshot must never allow resurrect.
      final local = _p(
        variacoes: {
          '20': {'prata': 0},
        },
        ept: const {'20': 1},
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(local);
      expect(c.allowResurrectFromEstoquePorTamanho, isFalse);
      expect(
        c.state,
        ProdutoVariationStockConsistencyState.localStaleEvidence,
      );
      expect(c.blocksSilentZeroSave, isTrue);
      expect(c.blocksPdvSale, isTrue);

      final h = produtoFormHydrateGradeRows(local);
      expect(h.rows.single['qtd'], '0'); // still 0 from variacoes
      expect(h.consistency?.allowResurrectFromEstoquePorTamanho, isFalse);

      // After authoritative remote all-zero arrives:
      final remote = _p(
        variacoes: {
          '20': {'prata': 0},
        },
        ept: const {'20': 0},
      );
      final after =
          ProdutoVariationStockConsistencyEvaluator.evaluateProduto(remote);
      expect(after.state, ProdutoVariationStockConsistencyState.consistent);
      expect(after.variationQtySum, 0);
      expect(produtoFormHydrateGradeRows(remote).rows.single['qtd'], '0');
    });

    test('remote divergence: var=0 ept=1 unique mapping → recovery, no resurrect',
        () {
      final remote = _p(
        variacoes: {
          '45cm': {'sem-cor': 0},
        },
        ept: const {'45cm': 1},
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(
        remote,
        remoteAuthoritative: true,
      );
      expect(
        c.state,
        ProdutoVariationStockConsistencyState.remoteRepresentationDivergence,
      );
      expect(c.allowResurrectFromEstoquePorTamanho, isFalse);
      expect(c.blocksSilentZeroSave, isTrue);
      expect(c.blocksPdvSale, isTrue);
      expect(produtoFormHydrateGradeRows(remote).rows.single['qtd'], '0');
    });

    test('size-only stock map with two colors is ambiguous — no duplication', () {
      final p = _p(
        variacoes: {
          '18': {'azul': 0, 'rosa': 0},
        },
        ept: const {'18': 1},
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.state, ProdutoVariationStockConsistencyState.ambiguousMapping);
      expect(c.ambiguousSizes, contains('18'));
      expect(c.blocksPdvSale, isTrue);
      expect(c.allowResurrectFromEstoquePorTamanho, isFalse);

      final h = produtoFormHydrateGradeRows(p);
      expect(h.rows.length, 2);
      expect(h.rows.every((r) => r['qtd'] == '0'), isTrue);
    });

    test('incomplete grade: ept keys not in variation rows → incomplete state',
        () {
      final p = _p(
        variacoes: {
          '15': {'sem-cor': 1},
          '19': {'sem-cor': 1},
        },
        ept: const {'12': 1, '15': 1, '19': 1, '20': 2, '21': 2},
        quantidade: 7,
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.state, ProdutoVariationStockConsistencyState.incompleteGrade);
      expect(c.incompleteStockKeys, isNotEmpty);
      expect(c.blocksSilentZeroSave, isTrue);
      expect(c.blocksPdvSale, isTrue);
    });

    test('unresolved zero cannot be silently saved (flag)', () {
      final p = _p(
        variacoes: {
          '20': {'prata': 0},
        },
        ept: const {'20': 1},
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.isUnresolved, isTrue);
      expect(c.blocksSilentZeroSave, isTrue);
    });

    test('ambiguous stock sale blocked (flag)', () {
      final p = _p(
        variacoes: {
          '18': {'azul': 0, 'rosa': 0},
        },
        ept: const {'18': 1},
      );
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.blocksPdvSale, isTrue);
    });

    test('simple product (no variacoes) evaluator remains consistent empty', () {
      final p = _p(variacoes: null, ept: const {}, quantidade: 5);
      final c = ProdutoVariationStockConsistencyEvaluator.evaluateProduto(p);
      expect(c.state, ProdutoVariationStockConsistencyState.consistent);
      expect(c.blocksPdvSale, isFalse);
      expect(c.blocksSilentZeroSave, isFalse);
      final h = produtoFormHydrateGradeRows(p);
      expect(h.source, ProdutoFormGradeHydrationSource.nenhuma);
    });

    test('hydrating / offlinePartial block sale and save', () {
      final h = ProdutoVariationStockConsistencyEvaluator.evaluate(
        variacoes: null,
        estoquePorTamanho: const {},
        hydrating: true,
      );
      expect(h.state, ProdutoVariationStockConsistencyState.hydrating);
      expect(h.blocksPdvSale, isTrue);
      expect(h.message, 'Estoque em atualização');

      final o = ProdutoVariationStockConsistencyEvaluator.evaluate(
        variacoes: null,
        estoquePorTamanho: const {},
        offlinePartial: true,
      );
      expect(o.state, ProdutoVariationStockConsistencyState.offlinePartial);
      expect(o.blocksSilentZeroSave, isTrue);
    });
  });
}
