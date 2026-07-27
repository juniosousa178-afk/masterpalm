import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_policy.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'cryptographic_trust_anchor_validator.dart';
import 'cryptographic_trust_requirement_validator.dart';
import 'cryptographic_validation_helpers.dart';

/// Validates structural consistency of [CryptographicTrustPolicy].
class CryptographicTrustPolicyValidator {
  const CryptographicTrustPolicyValidator({
    CryptographicTrustRequirementValidator? requirementValidator,
    CryptographicTrustAnchorValidator? trustAnchorValidator,
  })  : _requirementValidator = requirementValidator ??
            const CryptographicTrustRequirementValidator(),
        _trustAnchorValidator =
            trustAnchorValidator ?? const CryptographicTrustAnchorValidator();

  final CryptographicTrustRequirementValidator _requirementValidator;
  final CryptographicTrustAnchorValidator _trustAnchorValidator;

  CryptographicValidationResult validate(CryptographicTrustPolicy policy) {
    final issues = <CryptographicValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void merge(CryptographicValidationResult result) {
      issues.addAll(result.issues);
      warnings.addAll(result.warnings);
      errors.addAll(result.errors);
    }

    void addError(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      errors.add(message);
      issues.add(
        CryptographicValidationIssue(
          code: code,
          path: path,
          severity: CryptographicIssueSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    void addWarning(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      warnings.add(message);
      issues.add(
        CryptographicValidationIssue(
          code: code,
          path: path,
          severity: CryptographicIssueSeverity.warning,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    if (policy.policyId.isEmpty) {
      addError('CT_POLICY_ID', 'policyId', 'policyId is required');
    }
    if (policy.version < 1) {
      addError(
        'CT_POLICY_VERSION',
        'version',
        'version must be >= 1',
      );
    }
    if (policy.name.isEmpty) {
      addError('CT_POLICY_NAME', 'name', 'name is required');
    }
    if (policy.createdAt.isEmpty) {
      addError('CT_POLICY_CREATED_AT', 'createdAt', 'createdAt is required');
    }
    if (policy.requirements.isEmpty) {
      addError(
        'CT_POLICY_REQUIREMENTS',
        'requirements',
        'requirements must not be empty',
      );
    }

    final requirementIds = <String>{};
    final trustAnchorIds =
        policy.trustAnchors.map((anchor) => anchor.trustAnchorId).toSet();

    for (final requirement in policy.requirements) {
      if (!requirementIds.add(requirement.requirementId)) {
        addError(
          'CT_POLICY_DUPLICATE_REQUIREMENT',
          'requirements',
          'duplicate requirementId: ${requirement.requirementId}',
          relatedId: requirement.requirementId,
        );
      }

      final referencedAnchorId = requirement.constraints['trustAnchorId'];
      if (referencedAnchorId != null &&
          referencedAnchorId.isNotEmpty &&
          !trustAnchorIds.contains(referencedAnchorId)) {
        addError(
          'CT_POLICY_ANCHOR_REFERENCE',
          'requirements.${requirement.requirementId}.constraints.trustAnchorId',
          'referenced trustAnchorId not found in trustAnchors: $referencedAnchorId',
          relatedId: requirement.requirementId,
        );
      }

      if (requirement.requireTrustAnchor && policy.trustAnchors.isEmpty) {
        addError(
          'CT_POLICY_ANCHOR_REQUIRED',
          'trustAnchors',
          'requirement ${requirement.requirementId} requires trust anchors',
          relatedId: requirement.requirementId,
        );
      }

      merge(_requirementValidator.validate(requirement));
    }

    final anchorIds = <String>{};
    for (final anchor in policy.trustAnchors) {
      if (!anchorIds.add(anchor.trustAnchorId)) {
        addError(
          'CT_POLICY_DUPLICATE_ANCHOR',
          'trustAnchors',
          'duplicate trustAnchorId: ${anchor.trustAnchorId}',
          relatedId: anchor.trustAnchorId,
        );
      }
      merge(_trustAnchorValidator.validate(anchor));
    }

    if (!isIsoDateRangeCoherent(policy.createdAt, policy.effectiveFrom)) {
      addError(
        'CT_POLICY_LIFECYCLE_EFFECTIVE',
        'effectiveFrom',
        'effectiveFrom must be >= createdAt',
      );
    }
    if (!isIsoDateRangeCoherent(policy.effectiveFrom, policy.deprecatedAt)) {
      addError(
        'CT_POLICY_LIFECYCLE_DEPRECATED',
        'deprecatedAt',
        'deprecatedAt must be >= effectiveFrom',
      );
    }
    if (!isIsoDateRangeCoherent(policy.deprecatedAt, policy.retiredAt)) {
      addError(
        'CT_POLICY_LIFECYCLE_RETIRED',
        'retiredAt',
        'retiredAt must be >= deprecatedAt',
      );
    }

    if (policy.status == CryptographicPolicyStatus.retired ||
        policy.status == CryptographicPolicyStatus.deprecated) {
      addWarning(
        'CT_POLICY_STATUS',
        'status',
        'policy status is ${policy.status.wireName}',
        relatedId: policy.policyId,
      );
    }

    validateSensitiveMetadata(
      policy.metadata,
      'metadata',
      addError,
      code: 'CT_POLICY_SENSITIVE_METADATA',
    );

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
