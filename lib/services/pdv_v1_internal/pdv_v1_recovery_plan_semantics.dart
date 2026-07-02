import 'pdv_v1_journal_record.dart';
import 'pdv_v1_recovery_models.dart';

const _forbiddenMalformedTransportKeys = <String>{
  'rawPayload',
  'rawPayloadSanitized',
  'rawPayloadType',
  'operationIdCandidate',
  'saleIdCandidate',
  'lojaIdCandidate',
  'protocolVersionCandidate',
  'redactedKeyCount',
  'estimatedPayloadSize',
  'rejectedNodeCount',
  'malformedEvidence',
};

/// Resultado puro da validação semântica de plannedActions.
class PdvV1RecoveryPlanSemanticsValidationResult {
  const PdvV1RecoveryPlanSemanticsValidationResult({
    required this.valid,
    this.reasonCode = '',
    this.violations = const [],
  });

  final bool valid;
  final String reasonCode;
  final List<String> violations;

  Map<String, dynamic> toJson() => {
        'valid': valid,
        'reasonCode': reasonCode,
        'violations': violations,
      };
}

/// Validador determinístico — não reordena nem remove duplicatas.
class PdvV1RecoveryPlanSemanticsValidator {
  const PdvV1RecoveryPlanSemanticsValidator();

  PdvV1RecoveryPlanSemanticsValidationResult validate(PdvV1RecoveryPlan plan) {
    final violations = <String>[];

    _scanForbiddenKeys(plan.toJson(), violations, prefix: 'plan');

    if (pdvV1RecoveryPlanIsMalformedBoundary(plan)) {
      if (plan.decision != PdvV1RecoveryDecision.manualInterventionRequired) {
        violations.add('malformed_boundary_requires_manual_decision');
      }
      if (!_actionsEqual(
        plan.plannedActions,
        const [
          PdvV1RecoveryPlannedAction.preserveMalformedEvidence,
          PdvV1RecoveryPlannedAction.surfaceManualIntervention,
        ],
      )) {
        violations.add('malformed_boundary_actions_invalid');
      }
      if (plan.reasonCode != pdvV1MalformedRecoveryReasonCode) {
        violations.add('malformed_boundary_reason_code_invalid');
      }
      if (plan.operationId.isNotEmpty || plan.saleId.isNotEmpty) {
        violations.add('malformed_boundary_identity_leak');
      }
      return _result(violations);
    }

    if (plan.decision == PdvV1RecoveryDecision.invalidInput) {
      violations.add('invalid_input_plan');
      return _result(violations);
    }

    if (_hasDuplicateActions(plan.plannedActions)) {
      violations.add('planned_actions_duplicate');
    }

    switch (plan.decision) {
      case PdvV1RecoveryDecision.noAction:
        if (plan.plannedActions.isNotEmpty) {
          violations.add('no_action_requires_empty_actions');
        }
        if (!pdvV1JournalStateIsTerminal(plan.currentState)) {
          violations.add('no_action_requires_terminal_current_state');
        }
        if (plan.targetState != plan.currentState) {
          violations.add('no_action_target_must_equal_current');
        }
        break;

      case PdvV1RecoveryDecision.deferUntilVerification:
        if (!_actionsEqual(
          plan.plannedActions,
          const [PdvV1RecoveryPlannedAction.verifyMarkerAgain],
        )) {
          violations.add('defer_requires_verify_marker_again_only');
        }
        if (plan.targetState != plan.currentState) {
          violations.add('defer_must_keep_state');
        }
        break;

      case PdvV1RecoveryDecision.replanRemoteStockTransaction:
        if (plan.currentState == PdvV1JournalState.prepared) {
          if (!_actionsEqual(
            plan.plannedActions,
            const [
              PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture,
              PdvV1RecoveryPlannedAction.awaitExternalIntegration,
            ],
          )) {
            violations.add('replan_prepared_actions_invalid');
          }
          if (plan.targetState != PdvV1JournalState.prepared) {
            violations.add('replan_prepared_target_invalid');
          }
        } else if (plan.currentState == PdvV1JournalState.remoteStockPending) {
          if (!_actionsEqual(
            plan.plannedActions,
            const [
              PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture,
              PdvV1RecoveryPlannedAction.persistPlannedTransitionFuture,
            ],
          )) {
            violations.add('replan_pending_actions_invalid');
          }
          if (plan.targetState != PdvV1JournalState.prepared) {
            violations.add('replan_pending_target_invalid');
          }
        } else {
          violations.add('replan_invalid_current_state');
        }
        if (!plan.requiresExternalIntegration) {
          violations.add('replan_requires_external_integration_flag');
        }
        break;

      case PdvV1RecoveryDecision.continueWithHiveUpsert:
        if (!_actionsEqual(
          plan.plannedActions,
          const [PdvV1RecoveryPlannedAction.persistPlannedTransitionFuture],
        )) {
          violations.add('continue_hive_upsert_actions_invalid');
        }
        if (plan.currentState != PdvV1JournalState.remoteStockPending) {
          violations.add('continue_hive_upsert_invalid_current_state');
        }
        if (plan.targetState != PdvV1JournalState.remoteStockApplied) {
          violations.add('continue_hive_upsert_invalid_target');
        }
        break;

      case PdvV1RecoveryDecision.insertHiveSaleOnce:
        if (!_actionsEqual(
          plan.plannedActions,
          const [
            PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
            PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          ],
        )) {
          violations.add('insert_hive_actions_invalid');
        }
        if (plan.currentState != PdvV1JournalState.remoteStockApplied) {
          violations.add('insert_hive_before_remote_stock_applied');
        }
        if (plan.targetState != PdvV1JournalState.hiveSalePending) {
          violations.add('insert_hive_invalid_target');
        }
        break;

      case PdvV1RecoveryDecision.reuseExistingHiveSale:
        if (!_actionsEqual(
          plan.plannedActions,
          const [
            PdvV1RecoveryPlannedAction.planReuseHiveSaleFuture,
            PdvV1RecoveryPlannedAction.awaitExternalIntegration,
          ],
        )) {
          violations.add('reuse_hive_actions_invalid');
        }
        if (plan.currentState != PdvV1JournalState.remoteStockApplied) {
          violations.add('reuse_hive_outside_remote_stock_applied');
        }
        if (plan.targetState != PdvV1JournalState.hiveSaleCompleted) {
          violations.add('reuse_hive_invalid_target');
        }
        break;

      case PdvV1RecoveryDecision.requireExternalIntegration:
        if (!_actionsEqual(
          plan.plannedActions,
          const [PdvV1RecoveryPlannedAction.awaitExternalIntegration],
        )) {
          violations.add('require_integration_actions_invalid');
        }
        if (plan.targetState != plan.currentState) {
          violations.add('require_integration_must_keep_target');
        }
        if (pdvV1JournalStateIsTerminal(plan.currentState)) {
          violations.add('require_integration_on_terminal');
        }
        break;

      case PdvV1RecoveryDecision.manualInterventionRequired:
        final manualOnly = _actionsEqual(
          plan.plannedActions,
          const [PdvV1RecoveryPlannedAction.surfaceManualIntervention],
        );
        final malformedManual = _actionsEqual(
          plan.plannedActions,
          const [
            PdvV1RecoveryPlannedAction.preserveMalformedEvidence,
            PdvV1RecoveryPlannedAction.surfaceManualIntervention,
          ],
        );
        if (!manualOnly && !malformedManual) {
          violations.add('manual_actions_invalid');
        }
        if (plan.targetState != PdvV1JournalState.manualInterventionRequired) {
          violations.add('manual_target_invalid');
        }
        if (_containsIntegrationAction(plan.plannedActions) &&
            plan.plannedActions.contains(
                PdvV1RecoveryPlannedAction.preserveMalformedEvidence)) {
          violations.add('malformed_manual_with_integration_action');
        }
        break;

      case PdvV1RecoveryDecision.invalidInput:
        break;
    }

    if (plan.targetState == PdvV1JournalState.operationCompleted &&
        plan.currentState != PdvV1JournalState.effectsCompleted &&
        plan.decision != PdvV1RecoveryDecision.noAction) {
      violations.add('operation_completed_before_effects_completed');
    }

    return _result(violations);
  }

  PdvV1RecoveryPlanSemanticsValidationResult _result(List<String> violations) {
    if (violations.isEmpty) {
      return const PdvV1RecoveryPlanSemanticsValidationResult(valid: true);
    }
    return PdvV1RecoveryPlanSemanticsValidationResult(
      valid: false,
      reasonCode: violations.first,
      violations: List<String>.unmodifiable(violations),
    );
  }

  void _scanForbiddenKeys(
    dynamic value,
    List<String> violations, {
    required String prefix,
  }) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_forbiddenMalformedTransportKeys.contains(key)) {
          violations.add('forbidden_key_$key');
        }
        _scanForbiddenKeys(entry.value, violations, prefix: '$prefix.$key');
      }
    } else if (value is List) {
      for (var i = 0; i < value.length; i++) {
        _scanForbiddenKeys(value[i], violations, prefix: '$prefix[$i]');
      }
    }
  }

  bool _actionsEqual(
    List<PdvV1RecoveryPlannedAction> actual,
    List<PdvV1RecoveryPlannedAction> expected,
  ) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  bool _hasDuplicateActions(List<PdvV1RecoveryPlannedAction> actions) {
    final seen = <PdvV1RecoveryPlannedAction>{};
    for (final action in actions) {
      if (seen.contains(action)) return true;
      seen.add(action);
    }
    return false;
  }

  bool _containsIntegrationAction(List<PdvV1RecoveryPlannedAction> actions) {
    return actions.contains(
          PdvV1RecoveryPlannedAction.awaitExternalIntegration,
        ) ||
        actions.contains(
          PdvV1RecoveryPlannedAction.planHiveInsertOnceFuture,
        ) ||
        actions.contains(
          PdvV1RecoveryPlannedAction.planReuseHiveSaleFuture,
        ) ||
        actions.contains(
          PdvV1RecoveryPlannedAction.planRemoteStockTransactionFuture,
        );
  }
}
