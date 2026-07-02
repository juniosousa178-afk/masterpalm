import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_hive_journal_repository.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_internal_models.dart';
import 'package:master_palm/services/pdv_v1_internal/pdv_v1_journal_record.dart';

const _boxName = 'pdv_v1_journal_test_box';

class _IsolatedSession {
  _IsolatedSession({required this.tempDir, required this.box});

  final Directory tempDir;
  Box<dynamic> box;
}

Future<_IsolatedSession> _openIsolatedBox() async {
  final tempDir = await Directory.systemTemp.createTemp('pdv_v1_box_iso_');
  Hive.init(tempDir.path);
  final box = await Hive.openBox<dynamic>(_boxName);
  return _IsolatedSession(tempDir: tempDir, box: box);
}

Future<void> _closeIsolatedBox(Directory tempDir) async {
  if (Hive.isBoxOpen(_boxName)) {
    await Hive.box(_boxName).close();
    await Hive.deleteBoxFromDisk(_boxName);
  }
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }
  expect(await tempDir.exists(), isFalse);
}

PdvV1JournalRecord _record(String opId) {
  return PdvV1JournalRecord(
    prepared: PdvV1PreparedSnapshot(
      protocolVersion: pdvV1ProtocolVersion,
      operationId: opId,
      saleId: 'sale-iso',
      lojaId: 'loja-iso',
      origem: PdvV1InternalOrigin.novaVendaPdvFuture,
      preparedAtEpochMs: 1700000000000,
      preparedSnapshot: const {'k': 1},
      snapshotHash: 'snap-iso',
      txItemsHash: 'tx-iso',
      isFiado: false,
      hasCombo: false,
      isEdicao: false,
      isCancelamento: false,
    ),
    state: PdvV1JournalState.remoteStockPending,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
    journalRevision: 0,
  );
}

void main() {
  group('Isolamento de Box temporária', () {
    test('duas execuções usam diretórios diferentes', () async {
      final a = await _openIsolatedBox();
      final b = await _openIsolatedBox();
      expect(a.tempDir.path, isNot(b.tempDir.path));
      await _closeIsolatedBox(a.tempDir);
      await _closeIsolatedBox(b.tempDir);
    });

    test('journal de uma Box não aparece na outra', () async {
      final a = await _openIsolatedBox();
      final repoA = PdvV1HiveJournalRepository(box: a.box);
      await repoA.persistIfRevisionMatches(
        operationId: 'op-iso-a',
        expectedJournalRevision: 0,
        candidateJournalRecord: _record('op-iso-a'),
      );
      await _closeIsolatedBox(a.tempDir);

      final b = await _openIsolatedBox();
      final repoB = PdvV1HiveJournalRepository(box: b.box);
      expect(await repoB.readByOperationId('op-iso-a'), isNull);

      await _closeIsolatedBox(b.tempDir);
    });

    test('reabertura no mesmo diretório preserva journal local', () async {
      final session = await _openIsolatedBox();
      var repo = PdvV1HiveJournalRepository(box: session.box);
      await repo.persistIfRevisionMatches(
        operationId: 'op-iso-local',
        expectedJournalRevision: 0,
        candidateJournalRecord: _record('op-iso-local'),
      );

      if (Hive.isBoxOpen(_boxName)) {
        await session.box.close();
      }
      Hive.init(session.tempDir.path);
      session.box = await Hive.openBox<dynamic>(_boxName);
      repo = PdvV1HiveJournalRepository(box: session.box);
      final outcome = await repo.readByOperationId('op-iso-local');
      expect(outcome, isNotNull);
      expect(outcome!.record.journalRevision, 0);

      await _closeIsolatedBox(session.tempDir);
    });

    test('teardown remove diretório e Box', () async {
      final session = await _openIsolatedBox();
      final dirPath = session.tempDir.path;
      await repoPut(session.box);
      await _closeIsolatedBox(session.tempDir);
      expect(Directory(dirPath).existsSync(), isFalse);
      expect(Hive.isBoxOpen(_boxName), isFalse);
    });
  });
}

Future<void> repoPut(Box<dynamic> box) async {
  final repo = PdvV1HiveJournalRepository(box: box);
  await repo.persistIfRevisionMatches(
    operationId: 'op-teardown',
    expectedJournalRevision: 0,
    candidateJournalRecord: _record('op-teardown'),
  );
}
