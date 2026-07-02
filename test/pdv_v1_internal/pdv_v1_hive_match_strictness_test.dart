import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_upsert_policy.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';

void main() {
  const policy = PdvV1HiveUpsertPolicy();

  group('PdvV1HiveSaleMatch strictness', () {
    test('hiveKey 0 + saleId/hash compatíveis permite reuse', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: 0, saleId: 'sale-1', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.reuseExisting);
      expect(r.hiveKey, 0);
    });

    test('hiveKey null gera manual', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: null, saleId: 'sale-1', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('hiveKey negativo gera manual', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: -1, saleId: 'sale-1', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('match Hive sem saleId gera manual', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(hiveKey: 1, saleId: '', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('match Hive com hash ausente gera manual', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(hiveKey: 1, saleId: 'sale-1', snapshotHash: ''),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('match Hive divergente gera manual', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
            hiveKey: 1,
            saleId: 'sale-OUTRO',
            snapshotHash: 'hash-1',
          ),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('match duplicado gera manual', () {
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
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('apenas um match totalmente compatível permite reuse', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: 9, saleId: 'sale-1', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.reuseExisting);
      expect(r.hiveKey, 9);
    });

    test('match inválido com válido gera manual', () {
      final r = policy.decide(
        saleId: 'sale-1',
        snapshotHash: 'hash-1',
        found: const [
          PdvV1HiveSaleMatch(
              hiveKey: 1, saleId: 'sale-1', snapshotHash: 'hash-1'),
          PdvV1HiveSaleMatch(hiveKey: 2, saleId: '', snapshotHash: 'hash-1'),
        ],
      );
      expect(r.decision, PdvV1HiveUpsertDecision.manualInterventionRequired);
    });

    test('primeiro Box.add retorna chave 0', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('pdv_v1_hive_key0_test_');
      Hive.init(tempDir.path);
      const boxName = 'pdv_v1_key0_box';
      final box = await Hive.openBox<dynamic>(boxName);
      try {
        final key = await box.add({'probe': true});
        expect(key, 0);
      } finally {
        if (Hive.isBoxOpen(boxName)) {
          await box.close();
          await Hive.deleteBoxFromDisk(boxName);
        }
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
