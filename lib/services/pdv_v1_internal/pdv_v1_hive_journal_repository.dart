import 'dart:async';

import 'package:hive/hive.dart';

import 'pdv_v1_initial_prepared_journal_create_repository.dart';
import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_journal_record.dart';
import 'pdv_v1_journal_repository.dart';
import 'pdv_v1_recovery_models.dart';
import 'pdv_v1_state_machine.dart';

/// Implementação Hive com [Box] injetada — box aberta fora deste módulo.
class PdvV1HiveJournalRepository
    implements
        PdvV1JournalRepository,
        PdvV1InitialPreparedJournalCreateRepository {
  PdvV1HiveJournalRepository({
    required Box<dynamic> box,
    PdvV1StateMachine? stateMachine,
  })  : _box = box,
        _stateMachine = stateMachine ?? const PdvV1StateMachine();

  final Box<dynamic> _box;
  final PdvV1StateMachine _stateMachine;
  final Map<String, Future<void>> _mutationTailsByOperationId = {};

  Future<T> _runSerializedMutation<T>(
    String operationId,
    Future<T> Function() action,
  ) {
    final key = operationId.trim();
    final previous = _mutationTailsByOperationId[key] ?? Future<void>.value();
    final gate = Completer<void>();
    final result = previous.then((_) => action()).whenComplete(gate.complete);
    _mutationTailsByOperationId[key] = gate.future;
    gate.future.whenComplete(() {
      if (identical(_mutationTailsByOperationId[key], gate.future)) {
        _mutationTailsByOperationId.remove(key);
      }
    });
    return result;
  }

  PdvV1JournalReadOutcome? _readOutcomeFromBoxKey(String key) {
    final raw = _box.get(key);
    if (raw == null) {
      return null;
    }
    return PdvV1JournalRecord.readOutcomeFromRaw(
      rawPayload: raw,
      storageKey: key,
    );
  }

  Future<void> _writeRecordToBox(String opId, PdvV1JournalRecord record) async {
    await _box.put(opId, record.toJson());
  }

  @override
  Future<PdvV1JournalReadOutcome?> readByOperationId(String operationId) async {
    final key = operationId.trim();
    if (key.isEmpty) {
      return null;
    }
    return _readOutcomeFromBoxKey(key);
  }

  Future<void> _putWithinQueue(PdvV1JournalRecord record) async {
    if (record.isMalformedReadOnly) {
      throw PdvV1MalformedJournalError(
        'Journal malformado não pode ser persistido como record normal.',
      );
    }
    final opId = record.operationId.trim();
    if (opId.isEmpty) {
      throw PdvV1ValidationError('operationId vazio no put.');
    }
    final existing = _readOutcomeFromBoxKey(opId);
    if (existing?.isMalformedReadOnly == true) {
      throw PdvV1MalformedJournalError(
        'Entrada malformada existente requer intervenção manual.',
      );
    }
    await _writeRecordToBox(opId, record);
  }

  @override
  Future<void> put(PdvV1JournalRecord record) async {
    if (record.isMalformedReadOnly) {
      throw PdvV1MalformedJournalError(
        'Journal malformado não pode ser persistido como record normal.',
      );
    }
    final opId = record.operationId.trim();
    if (opId.isEmpty) {
      throw PdvV1ValidationError('operationId vazio no put.');
    }
    return _runSerializedMutation(opId, () => _putWithinQueue(record));
  }

  Future<PdvV1JournalRecord> _transitionWithinQueue({
    required String operationId,
    required PdvV1JournalState to,
    required int updatedAtEpochMs,
    String ultimoErroSanitizado = '',
    int? vendaHiveKey,
  }) async {
    final opId = operationId.trim();
    final outcome = _readOutcomeFromBoxKey(opId);
    if (outcome == null) {
      throw PdvV1ValidationError('Journal não encontrado: $operationId');
    }
    if (outcome.isMalformedReadOnly) {
      throw PdvV1MalformedJournalError(
        'Journal malformado não pode ser transicionado.',
      );
    }
    final record = outcome.record;
    if (record.operationId != opId) {
      throw PdvV1ValidationError('operationId divergente no journal.');
    }
    final revisionBefore = record.journalRevision;
    final next = _stateMachine.transitionRecord(
      record,
      to,
      updatedAtEpochMs: updatedAtEpochMs,
      ultimoErroSanitizado: ultimoErroSanitizado,
      vendaHiveKey: vendaHiveKey,
    );
    final persisted = next.state != record.state
        ? next.copyWith(journalRevision: revisionBefore + 1)
        : next;
    await _putWithinQueue(persisted);
    return persisted;
  }

  @override
  Future<PdvV1JournalRecord> transition({
    required String operationId,
    required PdvV1JournalState to,
    required int updatedAtEpochMs,
    String ultimoErroSanitizado = '',
    int? vendaHiveKey,
  }) {
    final opId = operationId.trim();
    return _runSerializedMutation(
      opId,
      () => _transitionWithinQueue(
        operationId: operationId,
        to: to,
        updatedAtEpochMs: updatedAtEpochMs,
        ultimoErroSanitizado: ultimoErroSanitizado,
        vendaHiveKey: vendaHiveKey,
      ),
    );
  }

  Future<PdvV1JournalRecord> _reconcileRemoteStockPendingWithinQueue({
    required String operationId,
    required PdvV1RemoteStockResolution resolution,
    required int updatedAtEpochMs,
  }) async {
    final opId = operationId.trim();
    final outcome = _readOutcomeFromBoxKey(opId);
    if (outcome == null) {
      throw PdvV1ValidationError('Journal não encontrado: $operationId');
    }
    if (outcome.isMalformedReadOnly) {
      throw PdvV1MalformedJournalError(
        'Journal malformado não pode ser reconciliado.',
      );
    }
    final revisionBefore = outcome.record.journalRevision;
    final next = _stateMachine.reconcileRemoteStockPendingRecord(
      outcome.record,
      resolution,
      updatedAtEpochMs: updatedAtEpochMs,
    );
    if (next.state == outcome.record.state &&
        next.updatedAtEpochMs == outcome.record.updatedAtEpochMs) {
      return next;
    }
    final persisted = next.state != outcome.record.state
        ? next.copyWith(journalRevision: revisionBefore + 1)
        : next;
    await _putWithinQueue(persisted);
    return persisted;
  }

  @override
  Future<PdvV1JournalRecord> reconcileRemoteStockPending({
    required String operationId,
    required PdvV1RemoteStockResolution resolution,
    required int updatedAtEpochMs,
  }) {
    final opId = operationId.trim();
    return _runSerializedMutation(
      opId,
      () => _reconcileRemoteStockPendingWithinQueue(
        operationId: operationId,
        resolution: resolution,
        updatedAtEpochMs: updatedAtEpochMs,
      ),
    );
  }

  PdvV1JournalInitialCreateOutcome? _validateExpectedInitialForCreate(
    PdvV1JournalRecord expectedInitial,
  ) {
    final opId = expectedInitial.operationId.trim();
    if (expectedInitial.isMalformedReadOnly) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    if (expectedInitial.malformedEvidence != null) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    if (expectedInitial.state != PdvV1JournalState.prepared) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    if (expectedInitial.journalRevision != 0) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    if (!_isExactNonEmptyId(expectedInitial.operationId)) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    if (!_isExactNonEmptyId(expectedInitial.saleId)) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    if (opId != expectedInitial.saleId.trim()) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    try {
      expectedInitial.prepared.validateForFoundation7AA();
    } on PdvV1ValidationError {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    } on PdvV1ScopeNotSupportedError {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    final prepared = expectedInitial.prepared;
    if (prepared.isFiado ||
        prepared.hasCombo ||
        prepared.isEdicao ||
        prepared.isCancelamento) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.invalidExpectedInitial,
        operationId: opId,
      );
    }
    return null;
  }

  Future<PdvV1JournalInitialCreateOutcome>
      _createInitialPreparedIfAbsentWithinQueue(
    PdvV1JournalRecord expectedInitial,
    String opId,
  ) async {
    final raw = _box.get(opId);
    if (raw == null) {
      try {
        await _writeRecordToBox(opId, expectedInitial);
      } catch (_) {
        return PdvV1JournalInitialCreateOutcome(
          kind: PdvV1JournalInitialCreateOutcomeKind.unavailable,
          operationId: opId,
        );
      }
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.created,
        operationId: opId,
        journalRevision: 0,
        existingState: PdvV1JournalState.prepared,
        record: expectedInitial,
      );
    }

    final existingOutcome = PdvV1JournalRecord.readOutcomeFromRaw(
      rawPayload: raw,
      storageKey: opId,
    );
    if (existingOutcome.isMalformedReadOnly ||
        existingOutcome.record.isMalformedReadOnly) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.existingMalformed,
        operationId: opId,
        existingState: existingOutcome.record.state,
      );
    }

    final existing = existingOutcome.record;
    if (existing.state == PdvV1JournalState.prepared &&
        existing.journalRevision == 0 &&
        pdvV1InitialPreparedRecordSemanticallyIdentical(
          existing,
          expectedInitial,
        )) {
      return PdvV1JournalInitialCreateOutcome(
        kind: PdvV1JournalInitialCreateOutcomeKind.alreadyExistsIdentical,
        operationId: opId,
        journalRevision: 0,
        existingState: PdvV1JournalState.prepared,
        record: existing,
      );
    }

    return PdvV1JournalInitialCreateOutcome(
      kind: PdvV1JournalInitialCreateOutcomeKind.alreadyExistsConflict,
      operationId: opId,
      journalRevision: existing.journalRevision,
      existingState: existing.state,
    );
  }

  @override
  Future<PdvV1JournalInitialCreateOutcome> createInitialPreparedIfAbsent({
    required PdvV1JournalRecord expectedInitial,
  }) async {
    final invalid = _validateExpectedInitialForCreate(expectedInitial);
    if (invalid != null) {
      return invalid;
    }
    final opId = expectedInitial.operationId.trim();
    return _runSerializedMutation(
      opId,
      () => _createInitialPreparedIfAbsentWithinQueue(expectedInitial, opId),
    );
  }

  Future<PdvV1JournalPersistCasOutcome> _persistIfRevisionMatchesWithinQueue({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalRecord candidateJournalRecord,
  }) async {
    final opId = operationId.trim();
    final candidate = candidateJournalRecord;

    PdvV1JournalPersistCasOutcome reject({
      required int storedRevisionBefore,
      required int storedRevisionAfter,
      required String rejectionReasonCode,
      required PdvV1JournalState stateBefore,
      required PdvV1JournalState stateAfter,
      Map<String, dynamic>? storedSnapshot,
    }) {
      return PdvV1JournalPersistCasOutcome(
        accepted: false,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: storedRevisionBefore,
        storedRevisionAfter: storedRevisionAfter,
        rejectionReasonCode: rejectionReasonCode,
        operationId: opId,
        stateBefore: stateBefore,
        stateAfter: stateAfter,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
        storedSnapshot: storedSnapshot,
      );
    }

    if (opId.isEmpty) {
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'operation_id_vazio',
        stateBefore: candidate.state,
        stateAfter: candidate.state,
      );
    }

    if (candidate.isMalformedReadOnly) {
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'candidate_malformed_read_only',
        stateBefore: candidate.state,
        stateAfter: candidate.state,
      );
    }

    if (candidate.operationId.trim() != opId) {
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'identity_mismatch',
        stateBefore: candidate.state,
        stateAfter: candidate.state,
      );
    }

    final existingOutcome = _readOutcomeFromBoxKey(opId);

    if (existingOutcome == null) {
      if (expectedJournalRevision != 0) {
        return reject(
          storedRevisionBefore: -1,
          storedRevisionAfter: -1,
          rejectionReasonCode: 'stale_journal_revision',
          stateBefore: candidate.state,
          stateAfter: candidate.state,
        );
      }
      if (candidate.journalRevision != 0) {
        return reject(
          storedRevisionBefore: -1,
          storedRevisionAfter: -1,
          rejectionReasonCode: 'revision_mismatch',
          stateBefore: candidate.state,
          stateAfter: candidate.state,
        );
      }
      if (candidate.state != PdvV1JournalState.prepared &&
          candidate.state != PdvV1JournalState.remoteStockPending) {
        return reject(
          storedRevisionBefore: -1,
          storedRevisionAfter: -1,
          rejectionReasonCode: 'invalid_initial_state',
          stateBefore: candidate.state,
          stateAfter: candidate.state,
        );
      }
      await _writeRecordToBox(opId, candidate);
      return PdvV1JournalPersistCasOutcome(
        accepted: true,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: -1,
        storedRevisionAfter: 0,
        rejectionReasonCode: '',
        operationId: opId,
        stateBefore: candidate.state,
        stateAfter: candidate.state,
        recordPersisted: true,
        persistedOnlyToInjectedBox: true,
        storedSnapshot: candidate.toJson(),
      );
    }

    if (existingOutcome.isMalformedReadOnly) {
      final raw = _box.get(opId);
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'journal_malformed_persist_denied',
        stateBefore: PdvV1JournalState.manualInterventionRequired,
        stateAfter: PdvV1JournalState.manualInterventionRequired,
        storedSnapshot: raw is Map ? Map<String, dynamic>.from(raw) : null,
      );
    }

    final stored = existingOutcome.record;
    final stateBefore = stored.state;
    final revBefore = stored.journalRevision;
    final storedJson = stored.toJson();

    PdvV1JournalPersistCasOutcome acceptNoOp() {
      return PdvV1JournalPersistCasOutcome(
        accepted: true,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'no_semantic_change',
        operationId: opId,
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
        storedSnapshot: storedJson,
      );
    }

    if (pdvV1JournalStateIsTerminal(stateBefore)) {
      if (pdvV1JournalRecordPersistStructurallyIdentical(stored, candidate)) {
        return acceptNoOp();
      }
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'terminal_state_persist_denied',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (expectedJournalRevision != revBefore) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'stale_journal_revision',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (!pdvV1JournalPreparedIdentityMatches(
        stored.prepared, candidate.prepared)) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'identity_mismatch',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (!pdvV1JournalPreparedSnapshotContentEquals(
      stored.prepared,
      candidate.prepared,
    )) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'prepared_snapshot_mismatch',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    final stateChanged = candidate.state != stateBefore;

    if (!stateChanged) {
      if (pdvV1JournalRecordPersistStructurallyIdentical(stored, candidate)) {
        return acceptNoOp();
      }
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'same_state_semantic_mutation_not_supported',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (candidate.journalRevision < revBefore) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'revision_regress_denied',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (candidate.journalRevision == expectedJournalRevision) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'revision_increment_required',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (candidate.journalRevision != expectedJournalRevision + 1) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'revision_mismatch',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (!_stateMachine.canTransition(stateBefore, candidate.state)) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'invalid_state_transition',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    await _writeRecordToBox(opId, candidate);
    return PdvV1JournalPersistCasOutcome(
      accepted: true,
      expectedRevision: expectedJournalRevision,
      storedRevisionBefore: revBefore,
      storedRevisionAfter: candidate.journalRevision,
      rejectionReasonCode: '',
      operationId: opId,
      stateBefore: stateBefore,
      stateAfter: candidate.state,
      recordPersisted: true,
      persistedOnlyToInjectedBox: true,
      storedSnapshot: candidate.toJson(),
    );
  }

  @override
  Future<PdvV1JournalPersistCasOutcome> persistIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalRecord candidateJournalRecord,
  }) {
    final opId = operationId.trim();
    if (opId.isEmpty) {
      return Future.value(
        _persistIfRevisionMatchesWithinQueue(
          operationId: operationId,
          expectedJournalRevision: expectedJournalRevision,
          candidateJournalRecord: candidateJournalRecord,
        ),
      );
    }
    return _runSerializedMutation(
      opId,
      () => _persistIfRevisionMatchesWithinQueue(
        operationId: operationId,
        expectedJournalRevision: expectedJournalRevision,
        candidateJournalRecord: candidateJournalRecord,
      ),
    );
  }

  Future<PdvV1JournalSameStatePatchPersistOutcome>
      _persistAuthorizedSameStatePatchIfRevisionMatchesWithinQueue({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalSameStatePatch patch,
    required PdvV1JournalSameStatePatchAuthorization authorization,
  }) async {
    final opId = operationId.trim();

    PdvV1JournalSameStatePatchPersistOutcome reject({
      required int storedRevisionBefore,
      required int storedRevisionAfter,
      required String rejectionReasonCode,
      required PdvV1JournalState stateBefore,
      required PdvV1JournalState stateAfter,
      Map<String, dynamic>? storedSnapshot,
    }) {
      return PdvV1JournalSameStatePatchPersistOutcome(
        accepted: false,
        expectedRevision: expectedJournalRevision,
        storedRevisionBefore: storedRevisionBefore,
        storedRevisionAfter: storedRevisionAfter,
        rejectionReasonCode: rejectionReasonCode,
        operationId: opId,
        stateBefore: stateBefore,
        stateAfter: stateAfter,
        recordPersisted: false,
        persistedOnlyToInjectedBox: true,
        storedSnapshot: storedSnapshot,
      );
    }

    if (opId.isEmpty) {
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'operation_id_vazio',
        stateBefore: patch.expectedState,
        stateAfter: patch.expectedState,
      );
    }

    if (authorization.operationId.trim() != opId) {
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'identity_mismatch',
        stateBefore: patch.expectedState,
        stateAfter: patch.expectedState,
      );
    }

    final existingOutcome = _readOutcomeFromBoxKey(opId);
    if (existingOutcome == null) {
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'journal_not_found_for_patch',
        stateBefore: patch.expectedState,
        stateAfter: patch.expectedState,
      );
    }

    if (existingOutcome.isMalformedReadOnly) {
      final raw = _box.get(opId);
      return reject(
        storedRevisionBefore: -1,
        storedRevisionAfter: -1,
        rejectionReasonCode: 'journal_malformed_patch_denied',
        stateBefore: PdvV1JournalState.manualInterventionRequired,
        stateAfter: PdvV1JournalState.manualInterventionRequired,
        storedSnapshot: raw is Map ? Map<String, dynamic>.from(raw) : null,
      );
    }

    final stored = existingOutcome.record;
    final stateBefore = stored.state;
    final revBefore = stored.journalRevision;
    final storedJson = stored.toJson();

    final validationError = pdvV1ValidateSameStatePatchAuthorization(
      stored: stored,
      patch: patch,
      authorization: authorization,
      expectedJournalRevision: expectedJournalRevision,
    );
    if (validationError != null) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: validationError,
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    if (authorization.planFingerprint.journalRevisionAtPlan != revBefore ||
        authorization.planFingerprint.currentState != stateBefore) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'stale_journal_revision',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    final persisted = pdvV1JournalRecordApplyRetryableStageFailurePatch(
      stored,
      patch.failureCode,
    );

    if (persisted.state != stored.state ||
        persisted.createdAtEpochMs != stored.createdAtEpochMs ||
        persisted.updatedAtEpochMs != stored.updatedAtEpochMs ||
        persisted.vendaHiveKey != stored.vendaHiveKey ||
        !pdvV1DeepJsonStructuralEquals(
            persisted.subestados, stored.subestados) ||
        !pdvV1JournalPreparedIdentityMatches(
          stored.prepared,
          persisted.prepared,
        ) ||
        !pdvV1JournalPreparedSnapshotContentEquals(
          stored.prepared,
          persisted.prepared,
        )) {
      return reject(
        storedRevisionBefore: revBefore,
        storedRevisionAfter: revBefore,
        rejectionReasonCode: 'patch_semantic_mutation_denied',
        stateBefore: stateBefore,
        stateAfter: stateBefore,
        storedSnapshot: storedJson,
      );
    }

    await _writeRecordToBox(opId, persisted);
    return PdvV1JournalSameStatePatchPersistOutcome(
      accepted: true,
      expectedRevision: expectedJournalRevision,
      storedRevisionBefore: revBefore,
      storedRevisionAfter: persisted.journalRevision,
      rejectionReasonCode: '',
      operationId: opId,
      stateBefore: stateBefore,
      stateAfter: persisted.state,
      recordPersisted: true,
      persistedOnlyToInjectedBox: true,
      storedSnapshot: persisted.toJson(),
    );
  }

  @override
  Future<PdvV1JournalSameStatePatchPersistOutcome>
      persistAuthorizedSameStatePatchIfRevisionMatches({
    required String operationId,
    required int expectedJournalRevision,
    required PdvV1JournalSameStatePatch patch,
    required PdvV1JournalSameStatePatchAuthorization authorization,
  }) {
    final opId = operationId.trim();
    if (opId.isEmpty) {
      return Future.value(
        _persistAuthorizedSameStatePatchIfRevisionMatchesWithinQueue(
          operationId: operationId,
          expectedJournalRevision: expectedJournalRevision,
          patch: patch,
          authorization: authorization,
        ),
      );
    }
    return _runSerializedMutation(
      opId,
      () => _persistAuthorizedSameStatePatchIfRevisionMatchesWithinQueue(
        operationId: operationId,
        expectedJournalRevision: expectedJournalRevision,
        patch: patch,
        authorization: authorization,
      ),
    );
  }
}

bool _isExactNonEmptyId(String value) =>
    value.isNotEmpty && value == value.trim();
