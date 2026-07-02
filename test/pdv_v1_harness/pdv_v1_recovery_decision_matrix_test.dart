import 'package:flutter_test/flutter_test.dart';

import 'support/pdv_v1_contract.dart';

void main() {
  PdvV1JournalSnapshot journalOk({
    bool hive = false,
    String txHash = 'hash-ok',
  }) =>
      PdvV1JournalSnapshot(
        integro: true,
        protocolVersion: pdvV1ProtocolVersion,
        operationId: '11111111-2222-4333-8444-555555555555',
        saleId: '11111111-2222-4333-8444-555555555555',
        lojaId: pdvV1HarnessLojaFicticia,
        origem: pdvV1Origem,
        txItemsHash: txHash,
        snapshotHash: 'snap-hash',
        preparedSnapshotCompleto: true,
        vendaHiveKey: hive ? 42 : null,
        substates: {
          if (hive) PdvV1EffectSubstate.hiveSaleCompleted: true,
        },
      );

  PdvV1RemoteMarker marcadorOk({String hash = 'hash-ok'}) => PdvV1RemoteMarker(
        presente: true,
        validoV1: true,
        baixaAplicada: true,
        estornoAplicado: false,
        txItemsHash: hash,
        lojaId: pdvV1HarnessLojaFicticia,
        origem: pdvV1Origem,
        protocolVersion: pdvV1ProtocolVersion,
      );

  group('PDV V1 — matriz recovery (contrato)', () {
    test('1. mesmo device, journal íntegro, crash pós-baixa → reconstruir Hive',
        () {
      final d = pdvV1DecidirRecovery(PdvV1RecoveryContext(
        journal: journalOk(),
        marcador: marcadorOk(),
        vendaHiveExiste: false,
      ));
      expect(d, PdvV1RecoveryDecision.reconstructHiveFromJournal);
    });

    test('2. Hive apagado, journal íntegro → reconstruir', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: marcadorOk(),
          vendaHiveExiste: false,
        )),
        PdvV1RecoveryDecision.reconstructHiveFromJournal,
      );
    });

    test('3. Hive corrompido/duplicado saleId → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: marcadorOk(),
          vendaHiveKeysDuplicadasSaleId: 2,
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('4. browser reload, journal íntegro → reconstruir se Hive ausente',
        () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: marcadorOk(),
        )),
        PdvV1RecoveryDecision.reconstructHiveFromJournal,
      );
    });

    test('5. novo device, sem journal, FS ausente → manual', () {
      expect(
        pdvV1DecidirSemJournal(marcadorOk()),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('6. novo device, sem journal, FS existente → manual (não auto Hive)',
        () {
      expect(
        pdvV1DecidirSemJournal(marcadorOk()),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('7. journal ausente, marcador presente → manual', () {
      expect(pdvV1DecidirSemJournal(marcadorOk()),
          PdvV1RecoveryDecision.manualInterventionRequired);
    });

    test('8. journal corrompido → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: PdvV1JournalSnapshot(
            integro: false,
            protocolVersion: 1,
            operationId: 'x',
            saleId: 'x',
            lojaId: pdvV1HarnessLojaFicticia,
            origem: pdvV1Origem,
            txItemsHash: 'h',
            snapshotHash: 's',
            preparedSnapshotCompleto: false,
          ),
          marcador: marcadorOk(),
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('9. hash divergente → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(txHash: 'a'),
          marcador: marcadorOk(hash: 'b'),
          hashCompativel: false,
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('10. loja divergente → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: marcadorOk(),
          lojaAtivaCompativel: false,
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('11. origem != pdv → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: PdvV1JournalSnapshot(
            integro: true,
            protocolVersion: 1,
            operationId: 'x',
            saleId: 'x',
            lojaId: pdvV1HarnessLojaFicticia,
            origem: 'pos_pagamento',
            txItemsHash: 'h',
            snapshotHash: 's',
            preparedSnapshotCompleto: true,
          ),
          marcador: marcadorOk(),
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('12. marcador legado → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: PdvV1RemoteMarker(
            presente: true,
            validoV1: false,
            baixaAplicada: true,
            estornoAplicado: false,
            txItemsHash: 'hash-ok',
            lojaId: pdvV1HarnessLojaFicticia,
            origem: 'pos_pagamento',
            protocolVersion: 0,
          ),
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('13. marcador inválido/incompleto → manual', () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: const PdvV1RemoteMarker(
            presente: true,
            validoV1: true,
            baixaAplicada: false,
            estornoAplicado: false,
            txItemsHash: '',
            lojaId: pdvV1HarnessLojaFicticia,
            origem: pdvV1Origem,
            protocolVersion: 1,
          ),
        )),
        PdvV1RecoveryDecision.manualInterventionRequired,
      );
    });

    test('14. offline com journal+marcador válidos → reconstruir Hive local',
        () {
      expect(
        pdvV1DecidirRecovery(PdvV1RecoveryContext(
          journal: journalOk(),
          marcador: marcadorOk(),
          online: false,
        )),
        PdvV1RecoveryDecision.reconstructHiveFromJournal,
      );
    });

    test('snapshot incompleto proíbe TX remota', () {
      expect(
        pdvV1PodeIniciarTransacaoRemota(
          PdvV1JournalSnapshot(
            integro: true,
            protocolVersion: 1,
            operationId: 'x',
            saleId: 'x',
            lojaId: pdvV1HarnessLojaFicticia,
            origem: pdvV1Origem,
            txItemsHash: '',
            snapshotHash: '',
            preparedSnapshotCompleto: false,
          ),
        ),
        isFalse,
      );
    });
  });

  group('PDV V1 — HiveUpsertPorSaleId (contrato)', () {
    test('mesmo saleId + mesmo hash → reuso', () {
      expect(
        pdvV1DecidirHiveUpsert(PdvV1HiveUpsertContext(
          saleId: 'sale-1',
          snapshotHash: 'h1',
          existingHiveKey: 7,
          existingSnapshotHash: 'h1',
        )),
        PdvV1HiveUpsertDecision.reuseExisting,
      );
    });

    test('mesmo saleId + hash divergente → manual', () {
      expect(
        pdvV1DecidirHiveUpsert(PdvV1HiveUpsertContext(
          saleId: 'sale-1',
          snapshotHash: 'h2',
          existingHiveKey: 7,
          existingSnapshotHash: 'h1',
        )),
        PdvV1HiveUpsertDecision.manualInterventionRequired,
      );
    });

    test('duplicatas legado → manual', () {
      expect(
        pdvV1DecidirHiveUpsert(PdvV1HiveUpsertContext(
          saleId: 'sale-1',
          snapshotHash: 'h1',
          duplicateCount: 2,
        )),
        PdvV1HiveUpsertDecision.manualInterventionRequired,
      );
    });
  });
}
