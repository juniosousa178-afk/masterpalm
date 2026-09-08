import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/catalog_loading_store_name.dart';

void main() {
  group('CatalogLoadingStoreName', () {
    test('A: slug técnico + nome comercial → pill mostra nome comercial', () {
      const slug = 'crisdealbuquerque094';
      expect(
        CatalogLoadingStoreName.slugToStoreNameFallback(slug),
        'Crisdealbuquerque094',
      );
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: 'Cristal Pratas',
          slug: slug,
        ),
        'Cristal Pratas',
      );
    });

    test('B: nome comercial indisponível → fallback seguro sem crash', () {
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: null,
          slug: 'crisdealbuquerque094',
        ),
        'Crisdealbuquerque094',
      );
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: '   ',
          slug: '',
        ),
        'Catálogo',
      );
    });

    test('C: outra loja sem hardcode de cliente', () {
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: 'Loja da Maria',
          slug: 'maria123',
        ),
        'Loja da Maria',
      );
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: 'Cristal Pratas',
          slug: 'outra-loja',
        ),
        'Cristal Pratas',
      );
    });

    test('D: nome já correto não exige slug bonito', () {
      const slug = 'crisdealbuquerque094';
      final label = CatalogLoadingStoreName.resolvePillLabel(
        commercialName: 'Cristal Pratas',
        slug: slug,
      );
      expect(label, 'Cristal Pratas');
      expect(slug, 'crisdealbuquerque094');
    });

    test('E: falha/valores inválidos preservam fallback', () {
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: 'admin@loja.com',
          slug: 'maria-123',
        ),
        'Maria 123',
      );
      expect(
        CatalogLoadingStoreName.resolvePillLabel(
          commercialName: 'Minha Loja',
          slug: null,
        ),
        'Catálogo',
      );
      expect(
        () => CatalogLoadingStoreName.resolvePillLabel(
          commercialName: null,
          slug: null,
        ),
        returnsNormally,
      );
    });

    test('pickCommercialName ignora id/lojaId/slug', () {
      final picked = CatalogLoadingStoreName.pickCommercialName({
        'id': 'crisdealbuquerque094',
        'lojaId': 'crisdealbuquerque094',
        'slug': 'crisdealbuquerque094',
        'nome': 'Cristal Pratas',
        'name': 'Cris de Albuquerque Freire',
      });
      expect(picked, 'Cristal Pratas');
    });
  });
}
