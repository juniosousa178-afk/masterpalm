import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_estoque_grade_canonical_guard.dart';
import 'package:master_palm/core/produto_form_grade_hydration.dart';
import 'package:master_palm/models/produto.dart';

void main() {
  group('Zerar variação manual — merge canônico', () {
    test('push autoritativo por tamanho não repõe cor zerada do baseline', () {
      final base = {
        'P': {'Azul': 2, 'Rosa': 5},
        'M': {'Azul': 1},
      };
      final push = {
        'P': {'Azul': 2},
      };

      final merged = ProdutoEstoqueGradeCanonicalGuard.mesclarVariacoesComPrioridadePush(
        base: base,
        push: push,
      );

      expect(merged['P'], {'Azul': 2});
      expect(merged['M'], {'Azul': 1});
      expect(merged['P'], isNot(contains('Rosa')));
    });

    test('completeForEstoquePush com push parcial não restaura cor zerada', () {
      final baseline = ProdutoFormGradeBaseline.capture(
        Produto(
          nome: 'Teste',
          custoReal: 1,
          frete: 0,
          gastosFixos: 0,
          gastosVariaveis: 0,
          precoSugerido: 0,
          precoFinal: 10,
          quantidade: 7,
          precoUnitario: 10,
          categoria: 'X',
          dataEntrada: DateTime(2026, 6, 9),
          lojaId: 'loja-z',
          variacoes: {
            'P': {'Azul': 2, 'Rosa': 5},
          },
          estoquePorTamanho: const {'P': 7},
        ),
      );

      final result = ProdutoEstoqueGradeCanonicalGuard.completeForEstoquePush(
        lojaId: 'loja-z',
        produtoId: 'p1',
        variacoesPush: {
          'P': {'Azul': 2},
        },
        variacoesExtraPush: {},
        estoquePorTamPush: const {'P': 2},
        tamanhosPush: const ['P'],
        quantidade: 2,
        baseline: baseline,
        existingEstoqueData: {
          'variacoes': {
            'P': {'Azul': 2, 'Rosa': 5},
          },
          'estoquePorTamanho': {'P': 7},
        },
      );

      final pMap = result.variacoes['P'] as Map;
      expect(pMap['Azul'], 2);
      expect(pMap.containsKey('Rosa'), isFalse);
      expect(result.estoquePorTamanho['P'], 2);
    });

    test('campo ausente na UI continua preservado quando push não toca tamanho', () {
      final base = {
        'P': {'Azul': 2},
        'G': {'Verde': 4},
      };
      final push = {
        'P': {'Azul': 1},
      };

      final merged = ProdutoEstoqueGradeCanonicalGuard.mesclarVariacoesComPrioridadePush(
        base: base,
        push: push,
      );

      expect(merged['P'], {'Azul': 1});
      expect(merged['G'], {'Verde': 4});
    });
  });
}
