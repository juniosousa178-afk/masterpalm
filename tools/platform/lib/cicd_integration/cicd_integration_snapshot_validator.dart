import '../models/cicd_integration/cicd_integration_snapshot.dart';
import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';
import 'deployment_validator.dart';
import 'execution_validator.dart';
import 'pipeline_validator.dart';

/// Aggregate validation for CI/CD integration snapshots.
class CicdIntegrationSnapshotValidator {
  const CicdIntegrationSnapshotValidator({
    PipelineValidator? pipelineValidator,
    ExecutionValidator? executionValidator,
    DeploymentValidator? deploymentValidator,
  })  : _pipelineValidator = pipelineValidator ?? const PipelineValidator(),
        _executionValidator = executionValidator ?? const ExecutionValidator(),
        _deploymentValidator =
            deploymentValidator ?? const DeploymentValidator();

  final PipelineValidator _pipelineValidator;
  final ExecutionValidator _executionValidator;
  final DeploymentValidator _deploymentValidator;

  PipelineValidationResult validate(CicdIntegrationSnapshot snapshot) {
    final issues = <PipelineValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(PipelineValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    final metadata = snapshot.metadata;
    if (metadata.cicdIntegrationSnapshotId.isEmpty) {
      errors.add('cicdIntegrationSnapshotId is required');
      issues.add(
        const PipelineValidationIssue(
          code: 'CICD_SNAPSHOT_ID',
          path: 'metadata.cicdIntegrationSnapshotId',
          severity: PipelineValidationSeverity.critical,
          message: 'cicdIntegrationSnapshotId is required',
        ),
      );
    }
    if (snapshot.fingerprint.isEmpty) {
      errors.add('fingerprint is required');
    }
    if (metadata.fingerprint != snapshot.fingerprint) {
      errors.add('metadata fingerprint does not match snapshot fingerprint');
    }
    if (snapshot.identity != null &&
        snapshot.identity!.snapshotFingerprint != snapshot.fingerprint) {
      errors.add(
          'identity snapshotFingerprint does not match snapshot fingerprint');
    }

    if (snapshot.pipelineDefinition != null) {
      merge(_pipelineValidator.validate(snapshot.pipelineDefinition!));
    }
    if (snapshot.pipelineExecution != null) {
      merge(_executionValidator.validate(snapshot.pipelineExecution!));
    }
    if (snapshot.deploymentPlan != null) {
      merge(_deploymentValidator.validatePlan(snapshot.deploymentPlan!));
    }
    if (snapshot.deploymentResult != null) {
      merge(_deploymentValidator.validateResult(snapshot.deploymentResult!));
    }

    if (snapshot.pipelineExecution != null &&
        snapshot.pipelineDefinition != null &&
        snapshot.pipelineExecution!.definitionId !=
            snapshot.pipelineDefinition!.definitionId) {
      errors
          .add('pipelineExecution.definitionId must match pipelineDefinition');
      issues.add(
        PipelineValidationIssue(
          code: 'CICD_SNAPSHOT_EXEC_DEF',
          path: 'pipelineExecution.definitionId',
          severity: PipelineValidationSeverity.critical,
          message:
              'pipelineExecution.definitionId must match pipelineDefinition',
          relatedId: snapshot.pipelineExecution!.executionId,
        ),
      );
    }

    if (snapshot.deploymentPlan != null &&
        snapshot.pipelineExecution != null &&
        snapshot.deploymentPlan!.pipelineExecutionId != null &&
        snapshot.deploymentPlan!.pipelineExecutionId !=
            snapshot.pipelineExecution!.executionId) {
      warnings.add(
        'deploymentPlan.pipelineExecutionId differs from pipelineExecution',
      );
    }

    if (snapshot.deploymentResult != null &&
        snapshot.deploymentPlan != null &&
        snapshot.deploymentResult!.planId != snapshot.deploymentPlan!.planId) {
      errors.add('deploymentResult.planId must match deploymentPlan.planId');
    }

    if (snapshot.policyReference != null) {
      final ref = snapshot.policyReference!;
      if (ref.pipelineIntegrationPolicyId !=
          metadata.pipelineIntegrationPolicyId) {
        errors.add('policyReference pipelineIntegrationPolicyId mismatch');
      }
      if (ref.pipelineExecutionPolicyId != metadata.pipelineExecutionPolicyId) {
        errors.add('policyReference pipelineExecutionPolicyId mismatch');
      }
      if (ref.deploymentIntegrationPolicyId !=
          metadata.deploymentIntegrationPolicyId) {
        errors.add('policyReference deploymentIntegrationPolicyId mismatch');
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
