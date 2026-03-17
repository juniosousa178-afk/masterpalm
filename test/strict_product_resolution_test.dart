// test/strict_product_resolution_test.dart
// Testes para o modo estrito de resolução por nome.

import 'package:flutter_test/flutter_test.dart';

import 'package:master_palm/core/strict_product_resolution.dart';

void main() {
  tearDown(() {
    setStrictResolutionTestOverride(null);
  });

  group('reportProductResolvedByName', () {
    test('strict=true lança exceção com mensagem clara', () {
      setStrictResolutionTestOverride(true);

      expect(
        () => reportProductResolvedByName(
          lojaId: 'loja_a',
          fluxo: 'teste',
          nome: 'Produto X',
        ),
        throwsA(
          predicate<Exception>((e) =>
              e.toString().contains('modo estrito') &&
              e.toString().contains('ID-first') &&
              e.toString().contains('Informe/propague productId') &&
              e.toString().contains('Produto X') &&
              e.toString().contains('loja_a')),
        ),
      );
    });

    test('strict=false não lança exceção', () {
      setStrictResolutionTestOverride(false);

      expect(
        () => reportProductResolvedByName(
          lojaId: 'loja_a',
          fluxo: 'teste',
          nome: 'Produto Y',
        ),
        returnsNormally,
      );
    });

    test('mensagem orienta a propagar productId', () {
      setStrictResolutionTestOverride(true);

      try {
        reportProductResolvedByName(
          lojaId: 'loja',
          fluxo: 'fluxo_teste',
          nome: 'Nome',
        );
        fail('Deveria ter lançado');
      } on Exception catch (e) {
        expect(e.toString(), contains('productId'));
        expect(e.toString(), contains('fluxo_teste'));
      }
    });
  });
}
