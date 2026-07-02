import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_effect_completion_contract.dart';

/// Contrato sale_sync_completed vs operation_completed — design only.
void main() {
  group('PDV V1 — effect completion contract (Fase 6.5)', () {
    test('sale_sync_completed permitido sem operation_completed', () {
      final completed = {
        PdvV1JournalState.remoteStockApplied,
        PdvV1JournalState.hiveSaleCompleted,
        PdvV1JournalState.saleSyncCompleted,
      };
      expect(pdvV1CanMarkSaleSyncCompleted(completed), isTrue);
      expect(pdvV1CanMarkOperationCompleted(completed), isFalse);
      expect(pdvV1SaleSyncBeforeOperationAllowed(completed), isTrue);
    });

    test('operation_completed exige efeitos obrigatórios', () {
      final partial = {
        PdvV1JournalState.remoteStockApplied,
        PdvV1JournalState.hiveSaleCompleted,
        PdvV1JournalState.saleSyncCompleted,
        PdvV1JournalState.productCacheRefreshCompleted,
      };
      expect(pdvV1CanMarkOperationCompleted(partial), isFalse);

      final full = {
        ...partial,
        PdvV1JournalState.comboCapCompleted,
        PdvV1JournalState.syncRemoteCompleted,
      };
      expect(pdvV1CanMarkOperationCompleted(full), isTrue);
    });

    test('manual_intervention_required bloqueia ambos finais', () {
      final s = {
        PdvV1JournalState.remoteStockApplied,
        PdvV1JournalState.hiveSaleCompleted,
        PdvV1JournalState.saleSyncCompleted,
        PdvV1JournalState.manualInterventionRequired,
      };
      expect(pdvV1CanMarkSaleSyncCompleted(s), isFalse);
      expect(pdvV1CanMarkOperationCompleted(s), isFalse);
    });

    test('catálogo de subestados cobre gates', () {
      expect(pdvV1SubstateCatalog.length, greaterThanOrEqualTo(5));
      final opBlockers = pdvV1SubstateCatalog
          .where((s) => s.blocksOperationCompleted)
          .map((s) => s.state)
          .toSet();
      expect(opBlockers, contains(PdvV1JournalState.hiveSaleCompleted));
      expect(opBlockers, contains(PdvV1JournalState.comboCapCompleted));
    });

    test('declaração de escopo', () {
      expect(
        true,
        isTrue,
        reason: 'Contrato de estados — não pipeline V1 real. '
            'sale_sync ≠ operation_completed.',
      );
    });
  });
}
