import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/strict_product_resolution.dart';

/// Constantes do bug reportado pela cliente Lavile (loja real não usada nos testes).
const kBugRelogioNome = 'Relógio Cássio Oval';
const kBugAnelNome = 'Anel Shine Regulável';
const kBugRelogioProductId = 'produto-relogio';
const kBugAnelProductId = 'produto-anel';
const kBugRelogioSlug = 'lavile-joias-rel-gio-cassio-oval';
const kBugAnelSlug = 'anel-shine-regulavel';

void main() {
  group('cenário Lavile — linha Anel com productId stale do Relógio', () {
    test('detecta incoerência exata do bug reportado', () {
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: kBugRelogioNome,
          nomeExibido: kBugAnelNome,
        ),
        isTrue,
      );
    });

    test('slugs diferentes confirmam produtos distintos no cenário simulado', () {
      expect(kBugRelogioSlug, isNot(kBugAnelSlug));
      expect(kBugRelogioProductId, isNot(kBugAnelProductId));
    });
  });

  group('productIdIncoerenteComNomeExibido', () {
    test('detecta mismatch entre produto resolvido e nome da linha', () {
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: kBugRelogioNome,
          nomeExibido: kBugAnelNome,
        ),
        isTrue,
      );
    });

    test('não acusa incoerência quando nomes batem', () {
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: 'Anel Shine Regulável',
          nomeExibido: 'anel shine regulável',
        ),
        isFalse,
      );
    });

    test('não acusa incoerência quando algum nome está vazio', () {
      expect(
        productIdIncoerenteComNomeExibido(
          nomeProdutoResolvido: '',
          nomeExibido: 'Anel Shine Regulável',
        ),
        isFalse,
      );
    });
  });
}
