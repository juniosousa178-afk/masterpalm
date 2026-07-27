import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';

/// Validates structural consistency of registered pipeline execution policies.
class PipelineExecutionPolicyValidator {
  const PipelineExecutionPolicyValidator();

  PipelineValidationResult validate(RegisteredPipelineExecutionPolicy policy) {
    final issues = <PipelineValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message) {
      errors.add(message);
      issues.add(
        PipelineValidationIssue(
          code: code,
          path: path,
          severity: PipelineValidationSeverity.critical,
          message: message,
        ),
      );
    }

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      addError('CICD_PE_POL_ID', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'CICD_PE_POL_VERSION',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.displayName.isEmpty) {
      addError(
        'CICD_PE_POL_DISPLAY',
        'metadata.displayName',
        'displayName is required',
      );
    }
    if (policy.policy.policyId != metadata.policyId) {
      addError(
        'CICD_PE_POL_MISMATCH',
        'policy.policyId',
        'policy.policyId must match metadata.policyId',
      );
    }
    if (policy.policy.requiredTerminalOutcomes.isEmpty) {
      addError(
        'CICD_PE_POL_OUTCOMES',
        'policy.requiredTerminalOutcomes',
        'requiredTerminalOutcomes must not be empty',
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
