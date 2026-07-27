import '../models/cicd_integration/cicd_integration_policy_models.dart';
import '../models/cicd_integration/pipeline_enums.dart';
import '../models/cicd_integration/pipeline_validation_result.dart';

/// Validates structural consistency of registered pipeline integration policies.
class PipelineIntegrationPolicyValidator {
  const PipelineIntegrationPolicyValidator();

  PipelineValidationResult validate(
      RegisteredPipelineIntegrationPolicy policy) {
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
      addError('CICD_PI_POL_ID', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'CICD_PI_POL_VERSION',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.displayName.isEmpty) {
      addError(
        'CICD_PI_POL_DISPLAY',
        'metadata.displayName',
        'displayName is required',
      );
    }
    if (policy.policy.policyId != metadata.policyId) {
      addError(
        'CICD_PI_POL_MISMATCH',
        'policy.policyId',
        'policy.policyId must match metadata.policyId',
      );
    }
    if (policy.policy.requiredStageTypes.isEmpty) {
      addError(
        'CICD_PI_POL_STAGES',
        'policy.requiredStageTypes',
        'requiredStageTypes must not be empty',
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
