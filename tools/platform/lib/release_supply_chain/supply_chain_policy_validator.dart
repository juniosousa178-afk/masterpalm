import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of registered supply chain policies.
class SupplyChainPolicyValidator {
  const SupplyChainPolicyValidator();

  ReleaseSupplyChainValidationResult validate(
      RegisteredSupplyChainPolicy policy) {
    final issues = <ReleaseSupplyChainValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message) {
      errors.add(message);
      issues.add(
        ReleaseSupplyChainValidationIssue(
          code: code,
          path: path,
          severity: ReleaseSupplyChainValidationSeverity.critical,
          message: message,
        ),
      );
    }

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      addError('RSC_SC_POL_ID', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RSC_SC_POL_VERSION',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.displayName.isEmpty) {
      addError(
        'RSC_SC_POL_DISPLAY',
        'metadata.displayName',
        'displayName is required',
      );
    }
    if (policy.policy.policyId != metadata.policyId) {
      addError(
        'RSC_SC_POL_MISMATCH',
        'policy.policyId',
        'policy.policyId must match metadata.policyId',
      );
    }
    if (policy.policy.requiredStageTypes.isEmpty) {
      addError(
        'RSC_SC_POL_STAGES',
        'policy.requiredStageTypes',
        'requiredStageTypes must not be empty',
      );
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
