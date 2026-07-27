import '../models/release_governance/release_approval.dart';
import '../models/release_governance/release_context.dart';
import '../models/release_governance/release_governance_enums.dart';
import '../models/release_governance/release_governance_messages.dart';

/// Validates release approval artifacts.
class ReleaseApprovalValidator {
  const ReleaseApprovalValidator();

  ReleaseGovernanceValidationResult validate(
    ReleaseApproval approval, {
    ReleaseContext? releaseContext,
    String? referenceTime,
    bool requireEvidence = true,
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
          relatedId: approval.approvalId,
        ),
      );
    }

    if (approval.approvalId.trim().isEmpty) {
      addError('RG_APPROVAL_ID', 'approvalId', 'approvalId is required');
    }
    if (approval.releaseId.trim().isEmpty) {
      addError('RG_APPROVAL_RELEASE', 'releaseId', 'releaseId is required');
    }
    if (approval.approverId.trim().isEmpty) {
      addError('RG_APPROVER_ID', 'approverId', 'approverId is required');
    }
    if (approval.fingerprint.trim().isEmpty) {
      addError(
          'RG_APPROVAL_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }

    if (releaseContext != null &&
        approval.releaseId != releaseContext.releaseId) {
      addError(
        'RG_APPROVAL_RELEASE_MISMATCH',
        'releaseId',
        'approval releaseId does not match release context',
      );
    }

    if (releaseContext != null &&
        approval.scope.commitId != null &&
        approval.scope.commitId!.isNotEmpty &&
        approval.scope.commitId != releaseContext.commitId) {
      addError(
        'RG_APPROVAL_COMMIT_MISMATCH',
        'scope.commitId',
        'approval commit does not match release context',
      );
    }

    if (approval.authority.status != ReleaseAuthorityStatus.active) {
      addError(
        'RG_APPROVAL_AUTHORITY_INACTIVE',
        'authority.status',
        'approval authority is not active',
      );
    }

    if (!approval.authority.allowedApprovalTypes
        .contains(approval.approvalType)) {
      addError(
        'RG_APPROVAL_TYPE_NOT_ALLOWED',
        'approvalType',
        'approval type is not allowed for authority',
      );
    }

    if (approval.expiresAt != null &&
        approval.expiresAt!.compareTo(approval.validFrom) <= 0) {
      addError(
        'RG_APPROVAL_EXPIRES_BEFORE_VALID',
        'expiresAt',
        'expiresAt must be after validFrom',
      );
    }

    if (referenceTime != null &&
        approval.expiresAt != null &&
        approval.expiresAt!.compareTo(referenceTime) <= 0) {
      warnings.add('approval is expired at referenceTime');
    }

    if (approval.status == ReleaseApprovalStatus.revoked) {
      warnings.add('approval is revoked');
    }

    if (requireEvidence && approval.evidence.isEmpty) {
      addError(
        'RG_APPROVAL_EVIDENCE',
        'evidence',
        'approval evidence is required',
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
    ReleaseApprovalSet approvalSet, {
    ReleaseContext? releaseContext,
    String? referenceTime,
  }) {
    final issues = <ReleaseGovernanceValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    if (approvalSet.releaseId.trim().isEmpty) {
      errors.add('approvalSet releaseId is required');
    }

    final approvalIds = <String>{};
    for (final approval in approvalSet.approvals) {
      if (!approvalIds.add(approval.approvalId)) {
        errors.add('duplicate approvalId: ${approval.approvalId}');
      }
      final result = validate(
        approval,
        releaseContext: releaseContext,
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
