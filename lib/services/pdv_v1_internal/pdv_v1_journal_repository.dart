import 'pdv_v1_journal_record.dart';
import 'pdv_v1_recovery_models.dart';
import 'pdv_v1_state_machine.dart';

/// Contrato do repositório de journal — sem abertura de box.
abstract class PdvV1JournalRepository {
  Future<PdvV1JournalReadOutcome?> readByOperationId(String operationId);

  Future<void> put(PdvV1JournalRecord record);

  Future<PdvV1JournalRecord> transition({
    required String operationId,
    required PdvV1JournalState to,
    required int updatedAtEpochMs,
    String ultimoErroSanitizado = '',
    int? vendaHiveKey,
  });

  Future<PdvV1JournalRecord> reconcileRemoteStockPending({
    required String operationId,
    required PdvV1RemoteStockResolution resolution,
    required int updatedAtEpochMs,
  });

  Future<PdvV1JournalPersistCasOutcome> persistIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalRecord candidateJournalRecord,
  });

  Future<PdvV1JournalSameStatePatchPersistOutcome>
      persistAuthorizedSameStatePatchIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalSameStatePatch patch,
    required PdvV1JournalSameStatePatchAuthorization authorization,
  });
}
