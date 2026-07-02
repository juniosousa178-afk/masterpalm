import 'pdv_v1_hive_upsert_policy.dart';
import 'pdv_v1_internal_errors.dart';
import 'pdv_v1_internal_models.dart';
import 'pdv_v1_journal_record.dart';
import 'pdv_v1_state_machine.dart';
import 'pdv_v1_transaction_planner.dart';

/// Resultado serializável de pré-validação interna.
class PdvV1PreValidationResult {
  const PdvV1PreValidationResult({
    required this.scopeValid,
    required this.snapshotValid,
    this.plannerResult,
    this.hiveUpsertResult,
    this.transitionValid,
    this.errorCode = '',
    this.errorMessage = '',
  });

  final bool scopeValid;
  final bool snapshotValid;
  final PdvV1TransactionPlannerResult? plannerResult;
  final PdvV1HiveUpsertPolicyResult? hiveUpsertResult;
  final bool? transitionValid;
  final String errorCode;
  final String errorMessage;

  Map<String, dynamic> toJson() => {
        'scopeValid': scopeValid,
        'snapshotValid': snapshotValid,
        if (plannerResult != null) 'plannerResult': plannerResult!.toJson(),
        if (hiveUpsertResult != null)
          'hiveUpsertResult': hiveUpsertResult!.toJson(),
        if (transitionValid != null) 'transitionValid': transitionValid,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
      };
}

/// Fundação de pipeline — somente validação e decisão pura.
class PdvV1PipelineFoundation {
  PdvV1PipelineFoundation({
    PdvV1StateMachine? stateMachine,
    PdvV1TransactionPlanner? planner,
    PdvV1HiveUpsertPolicy? hiveUpsertPolicy,
  })  : _stateMachine = stateMachine ?? const PdvV1StateMachine(),
        _planner = planner ?? const PdvV1TransactionPlanner(),
        _hiveUpsertPolicy = hiveUpsertPolicy ?? const PdvV1HiveUpsertPolicy();

  final PdvV1StateMachine _stateMachine;
  final PdvV1TransactionPlanner _planner;
  final PdvV1HiveUpsertPolicy _hiveUpsertPolicy;

  PdvV1RemoteStockReconcileResult reconcileRemoteStockPending(
    PdvV1RemoteStockResolution resolution,
  ) {
    return _stateMachine.reconcileRemoteStockPending(resolution);
  }

  PdvV1JournalRecord applyRemoteStockReconciliation(
    PdvV1JournalRecord record,
    PdvV1RemoteStockResolution resolution, {
    required int updatedAtEpochMs,
  }) {
    return _stateMachine.reconcileRemoteStockPendingRecord(
      record,
      resolution,
      updatedAtEpochMs: updatedAtEpochMs,
    );
  }

  void validateScope(PdvV1PreparedSnapshot prepared) {
    prepared.validateForFoundation7AA();
  }

  void validateTransition(
    PdvV1JournalState from,
    PdvV1JournalState to,
  ) {
    _stateMachine.assertTransition(from, to);
  }

  PdvV1TransactionPlannerResult planRemoteStock({
    required PdvV1PreparedSnapshot prepared,
    required PdvV1RemoteMarkerInput marker,
    required List<PdvV1TxItemFrozen> txItems,
  }) {
    validateScope(prepared);
    return _planner.plan(
      prepared: prepared,
      marker: marker,
      txItems: txItems,
      txItemsHash: prepared.txItemsHash,
      snapshotHash: prepared.snapshotHash,
      lojaId: prepared.lojaId,
    );
  }

  PdvV1HiveUpsertPolicyResult decideHiveUpsert({
    required PdvV1PreparedSnapshot prepared,
    required List<PdvV1HiveSaleMatch> found,
  }) {
    validateScope(prepared);
    return _hiveUpsertPolicy.decide(
      saleId: prepared.saleId,
      snapshotHash: prepared.snapshotHash,
      found: found,
    );
  }

  PdvV1PreValidationResult preValidate({
    required PdvV1PreparedSnapshot prepared,
    PdvV1RemoteMarkerInput marker = const PdvV1RemoteMarkerInput.ausente(),
    List<PdvV1TxItemFrozen> txItems = const [],
    List<PdvV1HiveSaleMatch> hiveMatches = const [],
    PdvV1JournalState? transitionFrom,
    PdvV1JournalState? transitionTo,
  }) {
    var scopeValid = false;
    var snapshotValid = false;
    PdvV1TransactionPlannerResult? plannerResult;
    PdvV1HiveUpsertPolicyResult? hiveResult;
    bool? transitionValid;

    try {
      validateScope(prepared);
      scopeValid = true;
      snapshotValid = true;
    } on PdvV1InternalError catch (e) {
      return PdvV1PreValidationResult(
        scopeValid: false,
        snapshotValid: false,
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    if (txItems.isNotEmpty) {
      plannerResult = planRemoteStock(
        prepared: prepared,
        marker: marker,
        txItems: txItems,
      );
    }

    hiveResult = decideHiveUpsert(
      prepared: prepared,
      found: hiveMatches,
    );

    if (transitionFrom != null && transitionTo != null) {
      if (transitionFrom == PdvV1JournalState.remoteStockPending &&
          transitionTo == PdvV1JournalState.prepared) {
        return PdvV1PreValidationResult(
          scopeValid: scopeValid,
          snapshotValid: snapshotValid,
          plannerResult: plannerResult,
          hiveUpsertResult: hiveResult,
          transitionValid: false,
          errorCode: 'invalid_transition',
          errorMessage:
              'remoteStockPending → prepared exige reconcileRemoteStockPending.',
        );
      }
      try {
        validateTransition(transitionFrom, transitionTo);
        transitionValid = true;
      } on PdvV1InvalidTransitionError catch (e) {
        transitionValid = false;
        return PdvV1PreValidationResult(
          scopeValid: scopeValid,
          snapshotValid: snapshotValid,
          plannerResult: plannerResult,
          hiveUpsertResult: hiveResult,
          transitionValid: false,
          errorCode: e.code,
          errorMessage: e.message,
        );
      }
    }

    return PdvV1PreValidationResult(
      scopeValid: scopeValid,
      snapshotValid: snapshotValid,
      plannerResult: plannerResult,
      hiveUpsertResult: hiveResult,
      transitionValid: transitionValid,
    );
  }

  /// Qualquer tentativa de executar integração externa falha fechada.
  Never rejectExecution([String? detail]) {
    throw PdvV1ExecutionNotIntegratedError(detail);
  }

  void assertNotIntegratedExecution() {
    rejectExecution();
  }
}
