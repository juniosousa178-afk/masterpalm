import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_projection_contract.dart';

/// Contrato projeção produtos/catálogo — NÃO implementação real.
void main() {
  group('PDV V1 — projection recovery contract harness (Fase 6.4)', () {
    test('estoque_produtos é autoritativo; produtos é projeção', () {
      expect(
        pdvV1ProjectionIsAuthoritative(PdvV1ProjectionKind.estoqueProdutos),
        isTrue,
      );
      expect(
        pdvV1ProjectionIsAuthoritative(PdvV1ProjectionKind.produtosFirestore),
        isFalse,
      );
      expect(
        pdvV1ProjectionIsAuthoritative(PdvV1ProjectionKind.catalogoWeb),
        isFalse,
      );
    });

    test('retry projeção não altera baixa principal', () {
      expect(
        pdvV1ProjectionRetrySeguro(
          invocaBaixaPrincipal: false,
          invocaNovaVenda: false,
        ),
        isTrue,
      );
      expect(
        pdvV1ProjectionRetrySeguro(
          invocaBaixaPrincipal: true,
          invocaNovaVenda: false,
        ),
        isFalse,
      );
    });

    test('recovery reproject from authoritative após baixa', () {
      const state = PdvV1ProjectionState(
        kind: PdvV1ProjectionKind.catalogoWeb,
        productId: 'prod-sint-1',
        operationId: 'op-proj-1',
        substateCompleted: false,
      );
      expect(
        pdvV1DecidirProjectionRecovery(
          state: state,
          baixaPrincipalConcluida: true,
          journalIntegro: true,
        ),
        PdvV1ProjectionRecoveryDecision.reprojectFromAuthoritative,
      );
    });

    test('subestado completed → skip', () {
      const state = PdvV1ProjectionState(
        kind: PdvV1ProjectionKind.hiveProdutos,
        productId: 'prod-sint-1',
        operationId: 'op-proj-1',
        substateCompleted: true,
        lastProjectedOperationId: 'op-proj-1',
      );
      expect(
        pdvV1DecidirProjectionRecovery(
          state: state,
          baixaPrincipalConcluida: true,
          journalIntegro: true,
        ),
        PdvV1ProjectionRecoveryDecision.skipAlreadyProjected,
      );
    });

    test('chave idempotente por operationId + kind + productId', () {
      final key = pdvV1ProjectionIdempotencyKey(
        kind: PdvV1ProjectionKind.hiveProdutos,
        operationId: 'op-1',
        productId: 'p-1',
      );
      expect(key, 'op-1:hiveProdutos:p-1');
    });

    test('declaração de escopo e limitações', () {
      expect(
        true,
        isTrue,
        reason:
            'Contrato: recomposição via estoque_produtos + CatalogoWebAposEstoqueService. '
            'NÃO prova: write produtos dentro da TX atual será removido. '
            'NÃO prova: catálogo web idempotente hoje (best-effort + log). '
            'Produto zerado pode aparecer temporariamente — atraso aceitável pós-venda, '
            'subestado catalog_projection_* recomendado.',
      );
    });
  });
}
