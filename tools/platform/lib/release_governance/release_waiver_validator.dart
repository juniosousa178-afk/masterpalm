import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';
import '../models/release_governance/release_governance_policy.dart';
import '../models/release_governance/release_waiver.dart';

/// Validates release waiver artifacts.
class ReleaseWaiverValidator {
  const ReleaseWaiverValidator();

  ReleaseGovernanceValidationResult validate(
    ReleaseWaiver waiver, {
    ReleaseContext? releaseContext,
    ReleaseGovernancePolicy? policy,
    String? referenceTime,
  }) {
    final issues = <ReleaseGovernanceValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(String code, String path, String message) {
      errors.add(message);
      issues.add(
        ReleaseGovernanceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseGovernanceRuleSeverity.critical,
          message: message,
          relatedId: waiver.waiverId,
        ),
      );
    }

    if (waiver.waiverId.trim().isEmpty) {
      addError('RG_WAIVER_ID', 'waiverId', 'waiverId is required');
    }
    if (waiver.releaseId.trim().isEmpty) {
      addError('RG_WAIVER_RELEASE', 'releaseId', 'releaseId is required');
    }
    if (waiver.justification.trim().isEmpty) {
      addError('RG_WAIVER_JUSTIFICATION', 'justification',
          'justification is required');
    }
    if (waiver.fingerprint.trim().isEmpty) {
      addError(
          'RG_WAIVER_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }

    if (waiver.scope.releaseId.trim().isEmpty) {
      addError(
        'RG_WAIVER_GLOBAL_FORBIDDEN',
        'scope.releaseId',
        'global waiver without releaseId is forbidden',
      );
    }

    if (waiver.expiration.expiresAt.compareTo(waiver.expiration.validFrom) <=
        0) {
      addError(
        'RG_WAIVER_EXPIRATION',
        'expiration',
        'expiresAt must be after validFrom',
      );
    }

    if (policy?.waiverRules.expirationRequired == true &&
        waiver.expiration.expiresAt.isEmpty) {
      addError('RG_WAIVER_NO_EXPIRATION', 'expiration.expiresAt',
          'expiration is required');
    }

    if (releaseContext != null &&
        waiver.releaseId != releaseContext.releaseId) {
      addError(
        'RG_WAIVER_RELEASE_MISMATCH',
        'releaseId',
        'waiver releaseId does not match release context',
      );
    }

    if (releaseContext != null &&
        waiver.scope.commitId != null &&
        waiver.scope.commitId!.isNotEmpty &&
        waiver.scope.commitId != releaseContext.commitId) {
      addError(
        'RG_WAIVER_COMMIT_MISMATCH',
        'scope.commitId',
        'waiver commit does not match release context',
      );
    }

    if (waiver.authority.status != ReleaseAuthorityStatus.active) {
      addError(
        'RG_WAIVER_AUTHORITY_INACTIVE',
        'authority.status',
        'waiver authority is not active',
      );
    }

    if (policy?.waiverRules.criticalForbidden == true) {
      for (final ruleId in waiver.affectedRuleIds) {
        if (ruleId == 'RG001' ||
            ruleId == 'RG002' ||
            ruleId == 'RG004' ||
            ruleId == 'RG005') {
          addError(
            'RG_WAIVER_CRITICAL_FORBIDDEN',
            'affectedRuleIds',
            'waiver for critical-forbidden rule $ruleId is not allowed',
          );
        }
      }
    }

    if (policy?.waiverRules.evidenceRequired == true &&
        waiver.evidence.isEmpty) {
      addError('RG_WAIVER_EVIDENCE', 'evidence', 'waiver evidence is required');
    }

    if (policy?.waiverRules.compensatingControlsRequired == true &&
        releaseContext?.environment == ReleaseEnvironment.production &&
        waiver.compensatingControls.isEmpty) {
      addError(
        'RG_WAIVER_COMPENSATING_CONTROL',
        'compensatingControls',
        'compensating control is required for production waiver',
      );
    }

    if (referenceTime != null) {
      if (waiver.expiration.expiresAt.compareTo(referenceTime) <= 0) {
        warnings.add('waiver is expired at referenceTime');
      }
      if (waiver.expiration.validFrom.compareTo(referenceTime) > 0) {
        warnings.add('waiver is not yet valid at referenceTime');
      }
    }

    if (waiver.status == ReleaseWaiverStatus.revoked) {
      warnings.add('waiver is revoked');
    }
    if (waiver.status == ReleaseWaiverStatus.consumed) {
      warnings.add('waiver is consumed');
    }

    if (waiver.usageCount > waiver.maximumUses) {
      addError(
        'RG_WAIVER_USAGE_EXCEEDED',
        'usageCount',
        'usageCount exceeds maximumUses',
      );
    }

    return ReleaseGovernanceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  ReleaseGovernanceValidationResult validateSet(
    ReleaseWaiverSet waiverSet, {
    ReleaseContext? releaseContext,
    ReleaseGovernancePolicy? policy,
    String? referenceTime,
  }) {
    final issues = <ReleaseGovernanceValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    final waiverIds = <String>{};
    for (final waiver in waiverSet.waivers) {
      if (!waiverIds.add(waiver.waiverId)) {
        errors.add('duplicate waiverId: ${waiver.waiverId}');
      }
      final result = validate(
        waiver,
        releaseContext: releaseContext,
        policy: policy,
        referenceTime: referenceTime,
      );
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    return ReleaseGovernanceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
