import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_catalog_projection_v1_contract.dart';

/// Contrato projeção produtos/catálogo V1 — design only.
void main() {
  group('PDV V1 — catalog projection contract (Fase 6.5)', () {
    test('write produtos permanece na TX principal (decisão A)', () {
      expect(
        pdvV1ProdutosWriteDecisionFase65,
        PdvV1ProdutosWriteInTxDecision.remainInMainTransactionAsProjection,
      );
    });

    test('quatro efeitos de projeção definidos', () {
      expect(pdvV1CatalogEffectSpecs.length, 4);
      final kinds = pdvV1CatalogEffectSpecs.map((e) => e.kind).toSet();
      expect(kinds, contains(PdvV1CatalogEffectKind.productProjection));
      expect(kinds, contains(PdvV1CatalogEffectKind.catalogProjection));
    });

    test('projeção derivada nunca cria venda/baixa/estorno', () {
      expect(
        pdvV1ProjectionNeverMutatesStock(
          invokesMainBaixa: false,
          invokesEstorno: false,
          createsNewSale: false,
        ),
        isTrue,
      );
      expect(
        pdvV1ProjectionNeverMutatesStock(
          invokesMainBaixa: true,
          invokesEstorno: false,
          createsNewSale: false,
        ),
        isFalse,
      );
    });

    test('product_cache_refresh bloqueia operation_completed', () {
      final cache = pdvV1CatalogEffectSpecs.firstWhere(
        (e) => e.kind == PdvV1CatalogEffectKind.productCacheRefresh,
      );
      expect(cache.blocksOperationCompleted, isTrue);
      expect(cache.blocksSaleSync, isFalse);
    });

    test('catalog_projection não bloqueia sale_sync', () {
      final cat = pdvV1CatalogEffectSpecs.firstWhere(
        (e) => e.kind == PdvV1CatalogEffectKind.catalogProjection,
      );
      expect(cat.blocksSaleSync, isFalse);
      expect(cat.computableFromRemote, isTrue);
    });

    test('declaração de escopo', () {
      expect(
        true,
        isTrue,
        reason: 'Não remove transaction.set(produtos) do código atual. '
            'Opção B (pós-TX) exige staging comprovado — não adotada na 6.5. '
            'Não testa pipeline V1 real.',
      );
    });
  });
}
