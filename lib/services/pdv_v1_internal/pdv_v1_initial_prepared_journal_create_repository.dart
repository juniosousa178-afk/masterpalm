import 'pdv_v1_journal_record.dart';

/// Outcomes fechados da criação inicial condicional de journal prepared.
enum PdvV1JournalInitialCreateOutcomeKind {
  created,
  alreadyExistsIdentical,
  alreadyExistsConflict,
  existingMalformed,
  unavailable,
  invalidExpectedInitial,
}

/// Resultado tipado da criação inicial — sem exceção bruta nem Box exposto.
class PdvV1JournalInitialCreateOutcome {
  const PdvV1JournalInitialCreateOutcome({
    required this.kind,
    required this.operationId,
    this.journalRevision,
    this.existingState,
    this.record,
  });

  final PdvV1JournalInitialCreateOutcomeKind kind;
  final String operationId;
  final int? journalRevision;
  final PdvV1JournalState? existingState;
  final PdvV1JournalRecord? record;
}

/// Capability estreita — criação local sem sobrescrita de journal existente.
abstract interface class PdvV1InitialPreparedJournalCreateRepository {
  Future<PdvV1JournalInitialCreateOutcome> createInitialPreparedIfAbsent({
    required PdvV1JournalRecord expectedInitial,
  });
}
