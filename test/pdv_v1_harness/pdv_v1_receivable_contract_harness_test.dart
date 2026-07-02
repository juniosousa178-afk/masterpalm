import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_receivable_contract.dart';

/// Contrato fiado/conta a receber — NÃO implementação real.
/// Nenhum pipeline V1 existe ainda. Nenhum dado de produção é usado.
void main() {
  group('PDV V1 — receivable contract harness (Fase 6.4)', () {
    test('chave saleId:conta_receber é determinística por parcela', () {
      const saleId = '00000000-0000-4000-8000-000000000001';
      final k1 =
          pdvV1ReceivableIdempotencyKey(saleId: saleId, parcelaNumero: 1);
      final k2 =
          pdvV1ReceivableIdempotencyKey(saleId: saleId, parcelaNumero: 2);
      expect(k1, contains('conta_receber'));
      expect(k1, isNot(equals(k2)));
      expect(
        pdvV1ReceivableFirestoreDocId(k1),
        startsWith('cr_'),
      );
    });

    test('create duplicado bloqueado pelo contrato', () {
      final chaves = <String>{};
      const saleId = 'sale-demo-64';
      expect(
        pdvV1ContratoBloqueiaCreateDuplicado(
          chavesJaCriadas: chaves,
          saleId: saleId,
          parcela: 1,
        ),
        isFalse,
      );
      expect(
        pdvV1ContratoBloqueiaCreateDuplicado(
          chavesJaCriadas: chaves,
          saleId: saleId,
          parcela: 1,
        ),
        isTrue,
      );
    });

    test('journal íntegro + conta existente → reuseExisting', () {
      final d = pdvV1DecidirReceivableUpsert(
        const PdvV1ReceivableRecoveryContext(
          journalIntegro: true,
          saleId: 'sale-1',
          parcelaNumero: 1,
          hiveContaExiste: true,
          vendaHiveExiste: true,
          existingParcelaValor: 100,
          requestedParcelaValor: 100,
        ),
      );
      expect(d, PdvV1ReceivableUpsertDecision.reuseExisting);
    });

    test('mesmo saleId valor divergente → manual_intervention_required', () {
      final d = pdvV1DecidirReceivableUpsert(
        const PdvV1ReceivableRecoveryContext(
          journalIntegro: true,
          saleId: 'sale-1',
          parcelaNumero: 1,
          hiveContaExiste: true,
          vendaHiveExiste: true,
          existingParcelaValor: 100,
          requestedParcelaValor: 150,
        ),
      );
      expect(d, PdvV1ReceivableUpsertDecision.manualInterventionRequired);
    });

    test('conta sem venda Hive → manual_intervention_required', () {
      final d = pdvV1DecidirReceivableUpsert(
        const PdvV1ReceivableRecoveryContext(
          journalIntegro: true,
          saleId: 'sale-1',
          parcelaNumero: 1,
          firestoreContaExiste: true,
          vendaHiveExiste: false,
        ),
      );
      expect(d, PdvV1ReceivableUpsertDecision.manualInterventionRequired);
    });

    test('declaração de escopo — contrato, não pipeline real', () {
      expect(
        true,
        isTrue,
        reason: 'Contrato avaliado: upsert por saleId+parcela. '
            'NÃO prova: _persistirContasReceberNaBox atual (crBox.add sem dedup). '
            'NÃO prova: recovery PDV V1 inexistente. '
            'Produção: hiveJaTemContaSemantica + upsertContaReceber existem e são reutilizáveis.',
      );
    });
  });
}
