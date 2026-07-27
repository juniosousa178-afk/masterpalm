import '../models/release_supply_chain/compliance_models.dart';
import '../models/release_supply_chain/release_supply_chain_enums.dart';
import '../models/release_supply_chain/release_supply_chain_validation_result.dart';

/// Validates structural consistency of [ComplianceResult].
class ComplianceValidator {
  const ComplianceValidator();

  ReleaseSupplyChainValidationResult validate(ComplianceResult result) {
    final issues = <ReleaseSupplyChainValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message,
        {String? relatedId}) {
      errors.add(message);
      issues.add(
        ReleaseSupplyChainValidationIssue(
          code: code,
          path: path,
          severity: ReleaseSupplyChainValidationSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    if (result.resultId.isEmpty) {
      addError('RSC_COMP_ID', 'resultId', 'resultId is required');
    }
    if (result.fingerprint.isEmpty) {
      addError(
          'RSC_COMP_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (result.policy.rules.isEmpty) {
      addError(
          'RSC_COMP_POLICY_RULES', 'policy.rules', 'policy must have rules');
    }

    final checkIds = <String>{};
    for (final check in result.checks) {
      if (!checkIds.add(check.checkId)) {
        addError(
          'RSC_COMP_DUPLICATE_CHECK',
          'checks',
          'duplicate checkId: ${check.checkId}',
          relatedId: check.checkId,
        );
      }
    }

    final violationIds = <String>{};
    for (final violation in result.violations) {
      if (!violationIds.add(violation.violationId)) {
        addError(
          'RSC_COMP_DUPLICATE_VIOLATION',
          'violations',
          'duplicate violationId: ${violation.violationId}',
          relatedId: violation.violationId,
        );
      }
    }

    if (result.status == ComplianceStatus.nonCompliant &&
        result.violations.isEmpty) {
      addError(
        'RSC_COMP_VIOLATIONS_REQUIRED',
        'violations',
        'nonCompliant status requires at least one violation',
      );
    }

    if (result.status == ComplianceStatus.partial) {
      warnings.add('compliance status is partial');
    }

    return ReleaseSupplyChainValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
