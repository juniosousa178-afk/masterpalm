import '../models/cicd_integration/deployment_models.dart';
import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';

/// Validates structural consistency of [DeploymentPlan] and [DeploymentResult].
class DeploymentValidator {
  const DeploymentValidator();

  PipelineValidationResult validatePlan(DeploymentPlan plan) {
    final issues = <PipelineValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      errors.add(message);
      issues.add(
        PipelineValidationIssue(
          code: code,
          path: path,
          severity: PipelineValidationSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    void addWarning(String code, String path, String message) {
      warnings.add(message);
      issues.add(
        PipelineValidationIssue(
          code: code,
          path: path,
          severity: PipelineValidationSeverity.warning,
          message: message,
        ),
      );
    }

    if (plan.planId.isEmpty) {
      addError('CICD_DEP_PLAN_ID', 'planId', 'planId is required');
    }
    if (plan.name.isEmpty) {
      addError('CICD_DEP_PLAN_NAME', 'name', 'name is required');
    }
    if (plan.targets.isEmpty) {
      addWarning(
          'CICD_DEP_TARGETS', 'targets', 'deployment plan has no targets');
    }

    final targetIds = <String>{};
    for (final target in plan.targets) {
      if (!targetIds.add(target.targetId)) {
        addError(
          'CICD_DEP_DUPLICATE_TARGET',
          'targets',
          'duplicate targetId: ${target.targetId}',
          relatedId: target.targetId,
        );
      }
      if (target.uri.isEmpty) {
        addError(
          'CICD_DEP_TARGET_URI',
          'targets',
          'target uri is required',
          relatedId: target.targetId,
        );
      }
    }

    final approvalIds = <String>{};
    for (final approval in plan.approvals) {
      if (!approvalIds.add(approval.approvalId)) {
        addError(
          'CICD_DEP_DUPLICATE_APPROVAL',
          'approvals',
          'duplicate approvalId: ${approval.approvalId}',
          relatedId: approval.approvalId,
        );
      }
    }

    final windowIds = <String>{};
    for (final window in plan.windows) {
      if (!windowIds.add(window.windowId)) {
        addError(
          'CICD_DEP_DUPLICATE_WINDOW',
          'windows',
          'duplicate windowId: ${window.windowId}',
          relatedId: window.windowId,
        );
      }
      if (window.startAt.compareTo(window.endAt) >= 0) {
        addError(
          'CICD_DEP_WINDOW_RANGE',
          'windows',
          'startAt must be before endAt',
          relatedId: window.windowId,
        );
      }
    }

    if (plan.strategy == DeploymentStrategy.canary && plan.targets.length < 2) {
      addWarning(
        'CICD_DEP_CANARY_TARGETS',
        'strategy',
        'canary strategy typically requires multiple targets',
      );
    }

    return PipelineValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  PipelineValidationResult validateResult(DeploymentResult result) {
    final issues = <PipelineValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      errors.add(message);
      issues.add(
        PipelineValidationIssue(
          code: code,
          path: path,
          severity: PipelineValidationSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    if (result.resultId.isEmpty) {
      addError('CICD_DEP_RESULT_ID', 'resultId', 'resultId is required');
    }
    if (result.planId.isEmpty) {
      addError('CICD_DEP_RESULT_PLAN', 'planId', 'planId is required');
    }
    if (result.startedAt.isEmpty) {
      addError('CICD_DEP_RESULT_STARTED', 'startedAt', 'startedAt is required');
    }

    final terminalStatuses = {
      DeploymentResultStatus.succeeded,
      DeploymentResultStatus.failed,
      DeploymentResultStatus.rolledBack,
      DeploymentResultStatus.cancelled,
      DeploymentResultStatus.partial,
    };
    if (terminalStatuses.contains(result.status) &&
        (result.completedAt == null || result.completedAt!.isEmpty)) {
      addError(
        'CICD_DEP_RESULT_COMPLETED',
        'completedAt',
        'completedAt is required for terminal status',
        relatedId: result.resultId,
      );
    }

    return PipelineValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
