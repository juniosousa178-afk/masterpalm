import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_plan_semantics.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulated_cas_store.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_recovery_simulation_coordinator.dart';

PdvV1PreparedSnapshot _prep() {
  return PdvV1PreparedSnapshot(
    protocolVersion: pdvV1ProtocolVersion,
    operationId: 'op-scope-1',
    saleId: 'sale-scope-1',
    lojaId: 'loja-scope-1',
    origem: PdvV1InternalOrigin.novaVendaPdvFuture,
    preparedAtEpochMs: 1700000000000,
    preparedSnapshot: const {'k': 1},
    snapshotHash: 'snap-scope-1',
    txItemsHash: 'tx-scope-1',
    isFiado: false,
    hasCombo: false,
    isEdicao: false,
    isCancelamento: false,
  );
}

void main() {
  final coordinator = PdvV1RecoverySimulationCoordinator();

  group('PdvV1Recovery simulation scope guard', () {
    test('três execuções completas iguais retornam JSON idêntico', () {
      final record = PdvV1JournalRecord(
        prepared: _prep(),
        state: PdvV1JournalState.remoteStockPending,
        createdAtEpochMs: 1,
        updatedAtEpochMs: 1,
      );
      final evidence = PdvV1RemoteVerificationEvidence(
        requestedOperationId: 'op-scope-1',
        requestedSaleId: 'sale-scope-1',
        requestedLojaId: 'loja-scope-1',
        requestedOrigin: pdvV1OrigemProtocolValue,
        requestedProtocolVersion: pdvV1ProtocolVersion,
        requestedTxItemsHash: 'tx-scope-1',
        verificationStatus:
            PdvV1RemoteVerificationStatus.markerAppliedCompatible,
        optionalMarker: const PdvV1RemoteMarkerInput(
          presente: true,
          protocolVersion: pdvV1ProtocolVersion,
          origem: pdvV1OrigemProtocolValue,
          lojaId: 'loja-scope-1',
          operationId: 'op-scope-1',
          saleId: 'sale-scope-1',
          baixaAplicada: true,
          txItemsHash: 'tx-scope-1',
        ),
        verificationSource: 'synthetic',
        verifiedAtEpochMs: 2,
      );
      final input = PdvV1RecoverySimulationInput(
        journalOutcome: PdvV1JournalReadOutcome(record: record),
        evidence: evidence,
      );
      final j1 = jsonEncode(coordinator.run(input).toJson());
      final j2 = jsonEncode(coordinator.run(input).toJson());
      final j3 = jsonEncode(coordinator.run(input).toJson());
      expect(j1, j2);
      expect(j2, j3);
    });

    test('coordenador não usa callback, Box, Firebase, Future ou UI', () async {
      final files = [
        'pdv_v1_recovery_simulated_cas_store.dart',
        'pdv_v1_recovery_plan_semantics.dart',
        'pdv_v1_recovery_simulation_coordinator.dart',
      ];
      final forbidden = [
        'FirebaseFirestore',
        'FirebaseAuth',
        'runTransaction',
        'Hive.openBox',
        'Box<',
        'SharedPreferences',
        'DateTime.now',
        'Uuid',
        'package:uuid',
        'BuildContext',
        'package:flutter/material',
        'package:flutter/widgets',
        'void Function',
        'Future<void> Function',
        'Future<',
      ];
      for (final name in files) {
        final file = File('lib/services/pdv_v1_internal/$name');
        final content = await file.readAsString();
        for (final token in forbidden) {
          expect(
            content.contains(token),
            isFalse,
            reason: '$name não deve conter $token',
          );
        }
      }
    });

    test('nenhum arquivo externo referencia os três módulos novos', () async {
      final tokens = [
        'PdvV1RecoverySimulatedCasStore',
        'PdvV1RecoveryPlanSemanticsValidator',
        'PdvV1RecoverySimulationCoordinator',
      ];
      final hits = <String>[];
      final roots = [
        Directory('lib/screens'),
        Directory('lib/services'),
        Directory('test'),
      ];
      for (final root in roots) {
        if (!await root.exists()) continue;
        await for (final entity in root.list(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('pdv_v1_internal')) continue;
          final content = await entity.readAsString();
          for (final token in tokens) {
            if (content.contains(token)) hits.add('${entity.path}:$token');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join(', '));
    });

    test('módulos novos não expõem parâmetros executáveis externos', () {
      expect(
        PdvV1RecoverySimulationCoordinator().run,
        isA<
            PdvV1RecoverySimulationRunOutcome Function(
              PdvV1RecoverySimulationInput,
            )>(),
      );
      expect(
        PdvV1RecoverySimulatedCasStore(
          PdvV1JournalRecord(
            prepared: _prep(),
            state: PdvV1JournalState.prepared,
            createdAtEpochMs: 1,
            updatedAtEpochMs: 1,
          ),
        ).snapshot,
        isA<PdvV1JournalRecord>(),
      );
      expect(
        const PdvV1RecoveryPlanSemanticsValidator().validate,
        isA<
            PdvV1RecoveryPlanSemanticsValidationResult Function(
              PdvV1RecoveryPlan,
            )>(),
      );
    });
  });
}
