import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final capabilitySource = File(
    'lib/services/pdv_v1_internal/'
    'pdv_v1_initial_prepared_journal_create_repository.dart',
  ).readAsStringSync();
  final hiveSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart',
  ).readAsStringSync();
  final journalRepoSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_journal_repository.dart',
  ).readAsStringSync();
  final writerSource = File(
    'lib/services/pdv_v1_internal/pdv_v1_prepared_journal_writer.dart',
  ).readAsStringSync();

  group('R2-C.4.1 initial prepared journal create scope guard', () {
    test('1. capability não importa Hive, Firebase, UI ou writer', () {
      final forbidden = [
        'package:hive',
        'Hive.',
        'cloud_firestore',
        'FirebaseFirestore',
        'FirebaseAuth',
        'BuildContext',
        'Widget',
        'pdv_v1_prepared_journal_writer',
        'pdv_v1_infrastructure',
        'pdv_v1_hive_journal_repository',
      ];
      for (final token in forbidden) {
        expect(capabilitySource.contains(token), isFalse, reason: token);
      }
    });

    test('2. PdvV1HiveJournalRepository implementa capability estreita', () {
      expect(
        hiveSource,
        contains('PdvV1InitialPreparedJournalCreateRepository'),
      );
      expect(hiveSource, contains('createInitialPreparedIfAbsent'));
    });

    test('3. PdvV1JournalRepository permanece inalterado em contrato', () {
      expect(journalRepoSource, contains('readByOperationId'));
      expect(journalRepoSource, contains('Future<void> put'));
      expect(
          journalRepoSource, isNot(contains('createInitialPreparedIfAbsent')));
      expect(
        journalRepoSource,
        isNot(contains('PdvV1InitialPreparedJournalCreateRepository')),
      );
    });

    test('4. gate por operationId, não global', () {
      expect(hiveSource, contains('_mutationTailsByOperationId'));
      expect(hiveSource, isNot(contains('_globalMutationLock')));
    });

    test('5. mutadores entram no mesmo helper de fila', () {
      expect(hiveSource, contains('_runSerializedMutation'));
      expect(hiveSource, contains('_putWithinQueue'));
      expect(hiveSource, contains('_transitionWithinQueue'));
      expect(hiveSource, contains('_reconcileRemoteStockPendingWithinQueue'));
      expect(hiveSource, contains('_createInitialPreparedIfAbsentWithinQueue'));
      expect(
        hiveSource,
        contains('_persistIfRevisionMatchesWithinQueue'),
      );
      expect(
        hiveSource,
        contains(
            '_persistAuthorizedSameStatePatchIfRevisionMatchesWithinQueue'),
      );
      final gateCount = '_runSerializedMutation'.allMatches(hiveSource).length;
      expect(gateCount, greaterThanOrEqualTo(6));
    });

    test('6. fila recupera cauda e não usa timer/delay/retry', () {
      expect(hiveSource, contains('.whenComplete(gate.complete)'));
      expect(hiveSource, contains('whenComplete(() {'));
      expect(hiveSource, isNot(contains('Future.delayed')));
      expect(hiveSource, isNot(contains('Timer')));
      expect(hiveSource, isNot(contains('retry')));
      expect(hiveSource, isNot(contains('backoff')));
    });

    test('7. createInitialPreparedIfAbsent não usa APIs públicas mutáveis', () {
      final createPublic = hiveSource
          .split(
            'Future<PdvV1JournalInitialCreateOutcome> createInitialPreparedIfAbsent',
          )[1]
          .split('_createInitialPreparedIfAbsentWithinQueue')[0];
      final createWithin = hiveSource
          .split(
            '_createInitialPreparedIfAbsentWithinQueue',
          )[1]
          .split('@override')[0];

      expect(createPublic, isNot(contains('readByOperationId(')));
      expect(createPublic, isNot(contains('await put(')));
      expect(createPublic, isNot(contains('transition(')));
      expect(createWithin, isNot(contains('readByOperationId(')));
      expect(createWithin, contains('_box.get(opId)'));
      expect(createWithin, contains('_writeRecordToBox'));
    });

    test('8. writer R2-C.4.2 depende exclusivamente da capability CAS',
        () async {
      // A. Dependência correta do writer
      expect(
        writerSource,
        contains('pdv_v1_initial_prepared_journal_create_repository.dart'),
      );
      expect(
        writerSource,
        contains('PdvV1InitialPreparedJournalCreateRepository'),
      );
      expect(writerSource, contains('initialPreparedJournalCreateRepository'));
      expect(writerSource, contains('createInitialPreparedIfAbsent'));
      expect(
        'createInitialPreparedIfAbsent'.allMatches(writerSource).length,
        1,
      );
      expect(writerSource, isNot(contains('PdvV1JournalRepository')));
      expect(writerSource, isNot(contains('journalRepository')));
      expect(writerSource, isNot(contains('journalRepository ??')));
      expect(writerSource, isNot(contains('?? journalRepository')));

      // B. Fronteira proibida do writer
      expect(writerSource, isNot(contains('package:meta/meta.dart')));
      expect(writerSource, isNot(contains('@visibleForTesting')));
      final writerForbidden = [
        'PdvV1HiveJournalRepository',
        'readByOperationId',
        '.put(',
        'Box<',
        'package:hive',
        'Hive.',
        'cloud_firestore',
        'FirebaseFirestore',
        'FirebaseAuth',
        'SharedPreferences',
        'package:uuid',
        'Uuid(',
        'UUID',
        'DateTime.now',
        'BuildContext',
        'Widget',
        'pdv_v1_infrastructure',
        'remoteStockPending',
        'transition(',
        'persistIfRevisionMatches',
        'applyOnce',
        'Timer',
        'Future.delayed',
        'retry',
        'backoff',
      ];
      for (final token in writerForbidden) {
        expect(writerSource.contains(token), isFalse, reason: token);
      }

      // C. Direção de dependência — capability não referencia writer
      expect(capabilitySource, isNot(contains('PdvV1PreparedJournalWriter')));
      expect(
        capabilitySource,
        isNot(contains('pdv_v1_prepared_journal_writer')),
      );

      // C. Ausência de call site produtivo fora de pdv_v1_internal
      final prodTokens = [
        'PdvV1InitialPreparedJournalCreateRepository',
        'createInitialPreparedIfAbsent',
        'PdvV1PreparedJournalWriter',
        'pdv_v1_prepared_journal_writer',
      ];
      final prodFiles = [
        'lib/screens/nova_venda_modal.dart',
        'lib/services/vendas_service.dart',
        'lib/services/estoque_transaction_service.dart',
      ];
      for (final path in prodFiles) {
        final file = File(path);
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        for (final token in prodTokens) {
          expect(content.contains(token), isFalse, reason: '$path:$token');
        }
      }
      for (final root in [
        'lib/services/pdv_v1_infrastructure',
        'test/pdv_v1_harness',
        'test/pdv_v1_rules_v1',
      ]) {
        final dir = Directory(root);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          final content = await entity.readAsString();
          for (final token in prodTokens) {
            expect(content.contains(token), isFalse,
                reason: '${entity.path}:$token');
          }
        }
      }
    });

    test('9. sem call site produtivo para capability, create ou writer',
        () async {
      final tokens = [
        'PdvV1InitialPreparedJournalCreateRepository',
        'createInitialPreparedIfAbsent',
        'PdvV1PreparedJournalWriter',
        'pdv_v1_prepared_journal_writer',
      ];
      final paths = [
        'lib/screens',
        'lib/services',
      ];
      for (final root in paths) {
        await for (final entity in Directory(root).list(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('pdv_v1_internal')) continue;
          final content = await entity.readAsString();
          for (final token in tokens) {
            expect(content.contains(token), isFalse,
                reason: '${entity.path}:$token');
          }
        }
      }
    });
  });
}
