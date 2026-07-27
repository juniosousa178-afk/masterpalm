import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_models.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';

/// Validates structural consistency of [PipelineDefinition].
class PipelineValidator {
  const PipelineValidator();

  PipelineValidationResult validate(PipelineDefinition definition) {
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

    if (definition.definitionId.isEmpty) {
      addError('CICD_DEF_ID', 'definitionId', 'definitionId is required');
    }
    if (definition.name.isEmpty) {
      addError('CICD_DEF_NAME', 'name', 'name is required');
    }
    if (definition.version < 1) {
      addError('CICD_DEF_VERSION', 'version', 'version must be >= 1');
    }
    if (definition.stages.isEmpty) {
      addWarning('CICD_DEF_STAGES', 'stages', 'pipeline has no stages');
    }

    final stageIds = <String>{};
    final stepIds = <String>{};
    for (final stage in definition.stages) {
      if (!stageIds.add(stage.stageId)) {
        addError(
          'CICD_DEF_DUPLICATE_STAGE',
          'stages',
          'duplicate stageId: ${stage.stageId}',
          relatedId: stage.stageId,
        );
      }
      if (stage.stageId.isEmpty) {
        addError(
          'CICD_STAGE_ID',
          'stages',
          'stageId is required',
          relatedId: stage.stageId,
        );
      }
      for (final step in stage.steps) {
        if (!stepIds.add(step.stepId)) {
          addError(
            'CICD_DEF_DUPLICATE_STEP',
            'stages.steps',
            'duplicate stepId: ${step.stepId}',
            relatedId: step.stepId,
          );
        }
        if (step.stepId.isEmpty) {
          addError(
            'CICD_STEP_ID',
            'stages.steps',
            'stepId is required',
            relatedId: step.stepId,
          );
        }
        for (final dep in step.dependsOn) {
          if (!stepIds.contains(dep) &&
              !definition.stages
                  .expand((s) => s.steps)
                  .any((s) => s.stepId == dep)) {
            addError(
              'CICD_STEP_DEPENDENCY',
              'stages.steps.dependsOn',
              'unknown dependency: $dep',
              relatedId: step.stepId,
            );
          }
        }
      }
    }

    final triggerIds = <String>{};
    for (final trigger in definition.triggers) {
      if (!triggerIds.add(trigger.triggerId)) {
        addError(
          'CICD_DEF_DUPLICATE_TRIGGER',
          'triggers',
          'duplicate triggerId: ${trigger.triggerId}',
          relatedId: trigger.triggerId,
        );
      }
    }

    final environmentIds = <String>{};
    for (final env in definition.environments) {
      if (!environmentIds.add(env.environmentId)) {
        addError(
          'CICD_DEF_DUPLICATE_ENV',
          'environments',
          'duplicate environmentId: ${env.environmentId}',
          relatedId: env.environmentId,
        );
      }
    }

    final artifactIds = <String>{};
    for (final artifact in definition.artifacts) {
      if (!artifactIds.add(artifact.artifactId)) {
        addError(
          'CICD_DEF_DUPLICATE_ARTIFACT',
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
