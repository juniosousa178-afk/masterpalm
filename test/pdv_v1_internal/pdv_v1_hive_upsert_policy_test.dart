import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_upsert_policy.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';

void main() {
  const policy = PdvV1HiveUpsertPolicy();

  group('PdvV1HiveUpsertPolicy', () {
    test('sem venda → insertOnce', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.insertOnce);
    });

    test('uma venda mesmo hash → reuseExisting', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: 42, saleId: 'sale-1', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.reuseExisting);
      expect(r.hiveKey, 42);
    });

    test('hash divergente → manualInterventionRequired', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
            hiveKey: 42,
            saleId: 'sale-1',
            snapshotHash: 'hash-OUTRO',
          ),
        ],
      );
      expect(
        r.decision,
        PdvV1HiveUpsertDecision.manualInterventionRequired,
      );
    });

    test('duas vendas mesmo saleId → manualInterventionRequired', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: 1, saleId: 'sale-1', snapshotHash: 'hash-1'),
          PdvV1HiveSaleMatch(
              hiveKey: 2, saleId: 'sale-1', snapshotHash: 'hash-1'),
        ],
      );
      expect(
        r.decision,
        PdvV1HiveUpsertDecision.manualInterventionRequired,
      );
    });
  });
}
