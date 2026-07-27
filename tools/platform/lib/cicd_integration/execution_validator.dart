import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_models.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';

/// Validates structural consistency of [PipelineExecution].
class ExecutionValidator {
  const ExecutionValidator();

  PipelineValidationResult validate(PipelineExecution execution) {
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

    if (execution.executionId.isEmpty) {
      addError('CICD_EXEC_ID', 'executionId', 'executionId is required');
    }
    if (execution.definitionId.isEmpty) {
      addError('CICD_EXEC_DEF_ID', 'definitionId', 'definitionId is required');
    }
    if (execution.startedAt.isEmpty) {
      addError('CICD_EXEC_STARTED', 'startedAt', 'startedAt is required');
    }

    final terminalStatuses = {
      PipelineStatus.succeeded,
      PipelineStatus.failed,
      PipelineStatus.cancelled,
      PipelineStatus.timedOut,
      PipelineStatus.skipped,
    };
    if (terminalStatuses.contains(execution.status) &&
        (execution.completedAt == null || execution.completedAt!.isEmpty)) {
      addError(
        'CICD_EXEC_COMPLETED',
        'completedAt',
        'completedAt is required for terminal status',
        relatedId: execution.executionId,
      );
    }

    if (execution.result != null) {
      final result = execution.result!;
      if (result.status != execution.status) {
        addError(
          'CICD_EXEC_RESULT_STATUS',
          'result.status',
          'result status must match execution status',
          relatedId: execution.executionId,
        );
      }
      if (result.outcome == PipelineExecutionOutcome.success &&
          execution.status != PipelineStatus.succeeded) {
        addError(
          'CICD_EXEC_OUTCOME',
          'result.outcome',
          'success outcome requires succeeded status',
          relatedId: execution.executionId,
        );
      }
      if (result.outcome == PipelineExecutionOutcome.failure &&
          execution.status != PipelineStatus.failed) {
        addError(
          'CICD_EXEC_OUTCOME',
          'result.outcome',
          'failure outcome requires failed status',
          relatedId: execution.executionId,
        );
      }
    } else if (terminalStatuses.contains(execution.status)) {
      addWarning(
        'CICD_EXEC_RESULT_MISSING',
        'result',
        'terminal execution has no result record',
      );
    }

    final artifactIds = <String>{};
    for (final artifact in execution.artifacts) {
      if (!artifactIds.add(artifact.artifactId)) {
        addError(
          'CICD_EXEC_DUPLICATE_ARTIFACT',
          'artifacts',
          'duplicate artifactId: ${artifact.artifactId}',
          relatedId: artifact.artifactId,
        );
      }
    }

    return PipelineValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
