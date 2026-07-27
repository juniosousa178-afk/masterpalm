import '../models/release_evidence/release_attestation_policy.dart';
import '../models/release_evidence/release_evidence_enums.dart';
import '../models/release_evidence/release_evidence_validation_result.dart';

/// Validates declarative attestation policies.
class ReleaseAttestationPolicyValidator {
  const ReleaseAttestationPolicyValidator();

  ReleaseEvidenceValidationResult validate(
    ReleaseAttestationPolicy policy, {
    bool allowRetired = false,
  }) {
    final issues = <ReleaseEvidenceValidationIssue>[];
    final warnings = <String>[];
    final errors = <String>[];

    void addError(
      String code,
      String path,
      String message, {
      String? relatedId,
    }) {
      errors.add(message);
      issues.add(
        ReleaseEvidenceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseEvidenceCollectionRuleSeverity.critical,
          message: message,
          relatedId: relatedId,
        ),
      );
    }

    void addWarning(String code, String path, String message) {
      warnings.add(message);
      issues.add(
        ReleaseEvidenceValidationIssue(
          code: code,
          path: path,
          severity: ReleaseEvidenceCollectionRuleSeverity.warning,
          message: message,
        ),
      );
    }

    final metadata = policy.metadata;
    if (metadata.policyId.isEmpty) {
      addError(
          'RA_POLICY_ID_REQUIRED', 'metadata.policyId', 'policyId is required');
    }
    if (metadata.policyVersion < 1) {
      addError(
        'RA_POLICY_VERSION_INVALID',
        'metadata.policyVersion',
        'policyVersion must be >= 1',
      );
    }
    if (metadata.owner.isEmpty) {
      addError('RA_OWNER_REQUIRED', 'metadata.owner', 'owner is required');
    }
    if (metadata.rationale.isEmpty) {
      addError('RA_RATIONALE_REQUIRED', 'metadata.rationale',
          'rationale is required');
    }
    if (!policy.compatibilityPolicy.supportedSchemas
        .contains(metadata.schemaVersion)) {
      addError(
        'RA_SCHEMA_UNSUPPORTED',
        'metadata.schemaVersion',
        'schemaVersion ${metadata.schemaVersion} is not supported',
      );
    }
    if (metadata.status == ReleaseEvidencePolicyStatus.retired &&
        !allowRetired) {
      addWarning(
        'RA_RETIRED_POLICY',
        'metadata.status',
        'retired policy should only be used with historicalEvaluation',
      );
    }

    if (policy.supportedAttestationTypes.isEmpty) {
      addError(
        'RA_ATTESTATION_TYPES_EMPTY',
        'supportedAttestationTypes',
        'supportedAttestationTypes must not be empty',
      );
    }
    if (policy.supportedPredicateTypes.isEmpty) {
      addError(
        'RA_PREDICATE_TYPES_EMPTY',
        'supportedPredicateTypes',
        'supportedPredicateTypes must not be empty',
      );
    }

    final requirementIds = <String>{};
    for (final requirement in policy.requiredAttestations) {
      if (!requirementIds.add(requirement.requirementId)) {
        addError(
          'RA_DUPLICATE_REQUIREMENT',
          'requiredAttestations',
          'duplicate requirementId: ${requirement.requirementId}',
          relatedId: requirement.requirementId,
        );
      }
      if (!policy.supportedAttestationTypes
          .contains(requirement.attestationType)) {
        addError(
          'RA_UNSUPPORTED_ATTESTATION_TYPE',
          'requiredAttestations.${requirement.requirementId}',
          'attestation type ${requirement.attestationType.wireName} is not supported',
          relatedId: requirement.requirementId,
        );
      }
      if (!policy.supportedPredicateTypes.contains(requirement.predicateType)) {
        addError(
          'RA_UNSUPPORTED_PREDICATE_TYPE',
          'requiredAttestations.${requirement.requirementId}',
          'predicate type ${requirement.predicateType.wireName} is not supported',
          relatedId: requirement.requirementId,
        );
      }
      if (requirement.required && !requirement.enabled) {
        addError(
          'RA_REQUIRED_DISABLED',
          'requiredAttestations.${requirement.requirementId}',
          'required attestation requirement cannot be disabled',
          relatedId: requirement.requirementId,
        );
      }
      if (requirement.signatureRequired &&
          policy.signaturePolicy.futureCapabilityOnly) {
        addWarning(
          'RA_SIGNATURE_FUTURE_CAPABILITY',
          'requiredAttestations.${requirement.requirementId}',
          'signature requirement declared as future capability only',
        );
      }
      if (requirement.externalVerificationRequired) {
        addWarning(
          'RA_EXTERNAL_VERIFICATION_UNSUPPORTED',
          'requiredAttestations.${requirement.requirementId}',
          'external verification is not supported locally',
        );
      }
    }

    final signature = policy.signaturePolicy;
    if (signature.signatureRequired &&
        signature.allowAbsentSignature &&
        !signature.futureCapabilityOnly) {
      addError(
        'RA_SIGNATURE_INCOHERENT',
        'signaturePolicy',
        'signatureRequired cannot coexist with allowAbsentSignature unless futureCapabilityOnly',
      );
    }
    if (signature.signatureRequired && signature.allowUnverifiedSignature) {
      addWarning(
        'RA_SIGNATURE_UNVERIFIED_ALLOWED',
        'signaturePolicy',
        'signature required but unverified signatures are allowed',
      );
    }

    if (policy.issuerRequirements.allowedIssuerTypes.isEmpty) {
      addError(
        'RA_ISSUER_TYPES_EMPTY',
        'issuerRequirements.allowedIssuerTypes',
        'allowedIssuerTypes must not be empty',
      );
    }

    if (policy.authorityRequirements.allowedAuthorityIds.isEmpty) {
      addWarning(
        'RA_AUTHORITY_IDS_EMPTY',
        'authorityRequirements.allowedAuthorityIds',
        'allowedAuthorityIds is empty',
      );
    }

    return ReleaseEvidenceValidationResult(
      isValid: errors.isEmpty,
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }
}
