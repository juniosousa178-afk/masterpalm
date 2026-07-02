import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_receivable_authority_contract.dart';

/// Contrato fiado Firestore-first — design only.
void main() {
  group('PDV V1 — receivable authority contract (Fase 6.5)', () {
    test('fonte autoritativa: Firestore primeiro', () {
      expect(
        pdvV1ReceivableAuthorityModelEscolhido,
        PdvV1ReceivableAuthorityModel.firestoreFirst,
      );
    });

    test('receivableId determinístico por saleId e parcela', () {
      expect(
        pdvV1ReceivableId(saleId: 'sale-abc', parcela: 2),
        'sale-abc:conta_receber:p2',
      );
    });

    test('mesmo receivableId + hash → reuseBoth', () {
      final d = pdvV1DecidirReceivableAuthority(
        const PdvV1ReceivableParcelContext(
          journalIntegro: true,
          saleId: 'sale-1',
          parcela: 1,
          receivableSnapshotHash: 'abc123',
          vendaHiveExiste: true,
          crHiveExiste: true,
          crFirestoreExiste: true,
          existingHash: 'abc123',
        ),
      );
      expect(d, PdvV1ReceivableRecoveryDecision.reuseBoth);
    });

    test('hash divergente → manual', () {
      final d = pdvV1DecidirReceivableAuthority(
        const PdvV1ReceivableParcelContext(
          journalIntegro: true,
          saleId: 'sale-1',
          parcela: 1,
          receivableSnapshotHash: 'newhash',
          vendaHiveExiste: true,
          crHiveExiste: true,
          crFirestoreExiste: true,
          existingHash: 'oldhash',
        ),
      );
      expect(d, PdvV1ReceivableRecoveryDecision.manualInterventionRequired);
    });

    test('recovery duplicado não cria segunda parcela', () {
      final keys = <String>{};
      expect(
        pdvV1ReceivableRecoveryDuplicadoSeguro(
          chavesProcessadas: keys,
          receivableId: 'sale-1:conta_receber:p1',
          hash: 'h1',
          hashExistente: 'h1',
        ),
        isTrue,
      );
      expect(
        pdvV1ReceivableRecoveryDuplicadoSeguro(
          chavesProcessadas: keys,
          receivableId: 'sale-1:conta_receber:p1',
          hash: 'h1',
          hashExistente: 'h1',
        ),
        isTrue,
      );
      expect(keys.length, 1);
    });

    test('FS existe / Hive não → import', () {
      final d = pdvV1DecidirReceivableAuthority(
        const PdvV1ReceivableParcelContext(
          journalIntegro: true,
          saleId: 'sale-1',
          parcela: 1,
          receivableSnapshotHash: 'h1',
          vendaHiveExiste: true,
          crFirestoreExiste: true,
        ),
      );
      expect(d, PdvV1ReceivableRecoveryDecision.importFirestoreToHive);
    });

    test('declaração de escopo', () {
      expect(
        true,
        isTrue,
        reason: 'Contrato V1 fiado — não implementação. '
            'Reutiliza upsertContaReceber + hiveJaTemContaSemantica (design). '
            'Exclusão/cancelamento fora V1 inicial.',
      );
    });
  });
}
