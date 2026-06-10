import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/produto_estoque_grade_canonical_guard.dart';
import 'package:master_palm/models/produto.dart';

void main() {
  group('Aviso grade remota incompleta — Grumet 50cm zerado', () {
    test('variacoes com zero e estoquePorTamanho vazio é grade completa', () {
      final variacoes = {
        '50cm': {'prata': 0},
      };
      final estoque = <String, int>{};

      expect(
        ProdutoEstoqueGradeCanonicalGuard.gradeCoreCompleta(
          variacoes: variacoes,
          estoquePorTamanho: estoque,
        ),
        isTrue,
      );
      expect(
        ProdutoEstoqueGradeCanonicalGuard.gradePushIncompleta(
          variacoes: variacoes,
          variacoesExtraTipo: {},
          estoquePorTamanho: estoque,
          tamanhos: ['50cm'],
        ),
        isFalse,
      );
    });

    test('resolveForRehydrate não emite aviso para remoto zerado legítimo', () {
      final local = Produto(
        nome: 'Corrente Grumet Duplo 3mm 50cm',
        custoReal: 10,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 50,
        quantidade: 0,
        precoUnitario: 50,
        categoria: 'Correntes',
        dataEntrada: DateTime(2026, 6, 10),
        lojaId: 'nathy-pratas-e-folheados',
        idFirebase: 'nathy-pratas-e-folheados-corrente-grumet-duplo-3mm-50cm',
        slug: 'nathy-pratas-e-folheados-corrente-grumet-duplo-3mm-50cm',
        variacoes: {'50cm': {'prata': 0}},
        estoquePorTamanho: {},
        tamanhos: ['50cm'],
      );

      final remoteData = {
        'quantidade': 0,
        'variacoes': {'50cm': {'prata': 0}},
        'estoquePorTamanho': <String, int>{},
        'tamanhos': ['50cm'],
      };

      final result = ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: local,
        remoteData: remoteData,
      );

      expect(result.aviso, isNull);
      expect(result.aplicarGradeRemota, isTrue);
    });

    test('grade remota realmente incompleta ainda protege', () {
      final local = Produto(
        nome: 'Produto grade',
        custoReal: 1,
        frete: 0,
        gastosFixos: 0,
        gastosVariaveis: 0,
        precoSugerido: 0,
        precoFinal: 10,
        quantidade: 2,
        precoUnitario: 10,
        categoria: 'X',
        dataEntrada: DateTime(2026, 6, 10),
        lojaId: 'loja',
        variacoes: {'P': {'sem-cor': 2}},
        estoquePorTamanho: {'P': 2},
        tamanhos: ['P'],
      );

      final remoteData = {
        'quantidade': 2,
        'tamanhos': ['P'],
      };

      final result = ProdutoEstoqueGradeCanonicalGuard.resolveForRehydrate(
        local: local,
        remoteData: remoteData,
      );

      expect(result.aviso, ProdutoEstoqueGradeCanonicalGuard.avisoGradeRemotaIncompleta);
      expect(result.aplicarGradeRemota, isFalse);
    });
  });
}
