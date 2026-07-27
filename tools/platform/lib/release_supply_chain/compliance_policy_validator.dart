import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_policy_models.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of registered compliance policies.
class CompliancePolicyValidator {
  const CompliancePolicyValidator();

  ReleaseSupplyChainValidationResult validate(
    RegisteredCompliancePolicy policy,
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
      addError('RSC_COMP_POL_ID', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RSC_COMP_POL_VERSION',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (policy.policy.policyId != metadata.policyId) {
      addError(
        'RSC_COMP_POL_MISMATCH',
        'policy.policyId',
        'policy.policyId must match metadata.policyId',
      );
    }
    if (policy.policy.rules.isEmpty) {
      addError(
        'RSC_COMP_POL_RULES',
        'policy.rules',
        'rules must not be empty',
      );
    }

    final ruleIds = <String>{};
    for (final rule in policy.policy.rules) {
      if (!ruleIds.add(rule.ruleId)) {
        addError(
          'RSC_COMP_POL_DUP_RULE',
          'policy.rules',
          'duplicate ruleId: ${rule.ruleId}',
        );
      }
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
