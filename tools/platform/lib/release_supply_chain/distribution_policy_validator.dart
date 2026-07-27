import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of registered distribution policies.
class DistributionPolicyValidator {
  const DistributionPolicyValidator();

  ReleaseSupplyChainValidationResult validate(
    RegisteredDistributionPolicy policy,
  ) {
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
      addError('RSC_DIST_POL_ID', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RSC_DIST_POL_VERSION',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (policy.policy.policyId != metadata.policyId) {
      addError(
        'RSC_DIST_POL_MISMATCH',
        'policy.policyId',
        'policy.policyId must match metadata.policyId',
      );
    }
    if (policy.policy.allowedChannelTypes.isEmpty) {
      addError(
        'RSC_DIST_POL_CHANNELS',
        'policy.allowedChannelTypes',
        'allowedChannelTypes must not be empty',
      );
    }
    if (policy.policy.requiredTargetCount < 1) {
      addError(
        'RSC_DIST_POL_TARGETS',
        'policy.requiredTargetCount',
        'requiredTargetCount must be >= 1',
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
