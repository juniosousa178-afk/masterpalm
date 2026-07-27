import '../models/cryptographic_trust/cryptographic_trust_enums.dart';
import '../models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import '../models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import '../models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'cryptographic_attestation_validator.dart';
import 'cryptographic_digest_validator.dart';
import 'cryptographic_key_reference_validator.dart';
import 'cryptographic_revocation_validator.dart';
import 'cryptographic_signature_envelope_validator.dart';
import 'cryptographic_signer_identity_validator.dart';
import 'cryptographic_trust_canonical_serializer.dart';
import 'cryptographic_trust_identity_builder.dart';
import 'cryptographic_transparency_log_reference_validator.dart';
import 'cryptographic_trust_anchor_validator.dart';
import 'cryptographic_trust_chain_validator.dart';
import 'cryptographic_trust_policy_validator.dart';
import 'cryptographic_trust_requirement_validator.dart';
import 'cryptographic_validation_helpers.dart';
import 'cryptographic_verification_request_validator.dart';
import 'cryptographic_verification_result_validator.dart';

/// Aggregate validation for cryptographic trust snapshots.
class CryptographicTrustSnapshotValidator {
  const CryptographicTrustSnapshotValidator({
    CryptographicDigestValidator? digestValidator,
    CryptographicKeyReferenceValidator? keyReferenceValidator,
    CryptographicSignatureEnvelopeValidator? signatureEnvelopeValidator,
    CryptographicAttestationValidator? attestationValidator,
    CryptographicTrustAnchorValidator? trustAnchorValidator,
    CryptographicTrustChainValidator? trustChainValidator,
    CryptographicTrustPolicyValidator? trustPolicyValidator,
    CryptographicVerificationRequestValidator? verificationRequestValidator,
    CryptographicVerificationResultValidator? verificationResultValidator,
    CryptographicRevocationValidator? revocationValidator,
    CryptographicTransparencyLogReferenceValidator?
        transparencyLogReferenceValidator,
    CryptographicSignerIdentityValidator? signerIdentityValidator,
    CryptographicTrustRequirementValidator? trustRequirementValidator,
    CryptographicTrustCanonicalSerializer? serializer,
    CryptographicTrustIdentityBuilder? identityBuilder,
  })  : _digestValidator =
            digestValidator ?? const CryptographicDigestValidator(),
        _keyReferenceValidator =
            keyReferenceValidator ?? const CryptographicKeyReferenceValidator(),
        _signatureEnvelopeValidator = signatureEnvelopeValidator ??
            const CryptographicSignatureEnvelopeValidator(),
        _attestationValidator =
            attestationValidator ?? const CryptographicAttestationValidator(),
        _trustAnchorValidator =
            trustAnchorValidator ?? const CryptographicTrustAnchorValidator(),
        _trustChainValidator =
            trustChainValidator ?? const CryptographicTrustChainValidator(),
        _trustPolicyValidator =
            trustPolicyValidator ?? const CryptographicTrustPolicyValidator(),
        _verificationRequestValidator = verificationRequestValidator ??
            const CryptographicVerificationRequestValidator(),
        _verificationResultValidator = verificationResultValidator ??
            const CryptographicVerificationResultValidator(),
        _revocationValidator =
            revocationValidator ?? const CryptographicRevocationValidator(),
        _transparencyLogReferenceValidator =
            transparencyLogReferenceValidator ??
                const CryptographicTransparencyLogReferenceValidator(),
        _signerIdentityValidator = signerIdentityValidator ??
            const CryptographicSignerIdentityValidator(),
        _trustRequirementValidator = trustRequirementValidator ??
            const CryptographicTrustRequirementValidator(),
        _serializer =
            serializer ?? const CryptographicTrustCanonicalSerializer(),
        _identityBuilder =
            identityBuilder ?? const CryptographicTrustIdentityBuilder();

  final CryptographicDigestValidator _digestValidator;
  final CryptographicKeyReferenceValidator _keyReferenceValidator;
  final CryptographicSignatureEnvelopeValidator _signatureEnvelopeValidator;
  final CryptographicAttestationValidator _attestationValidator;
  final CryptographicTrustAnchorValidator _trustAnchorValidator;
  final CryptographicTrustChainValidator _trustChainValidator;
  final CryptographicTrustPolicyValidator _trustPolicyValidator;
  final CryptographicVerificationRequestValidator _verificationRequestValidator;
  final CryptographicVerificationResultValidator _verificationResultValidator;
  final CryptographicRevocationValidator _revocationValidator;
  final CryptographicTransparencyLogReferenceValidator
      _transparencyLogReferenceValidator;
  final CryptographicSignerIdentityValidator _signerIdentityValidator;
  final CryptographicTrustRequirementValidator _trustRequirementValidator;
  final CryptographicTrustCanonicalSerializer _serializer;
  final CryptographicTrustIdentityBuilder _identityBuilder;

  CryptographicValidationResult validate(CryptographicTrustSnapshot snapshot) {
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

    final metadata = snapshot.metadata;
    final projectId = metadata.projectId;

    if (metadata.cryptographicTrustSnapshotId.isEmpty) {
      addError(
        'CT_SNAPSHOT_ID',
        'metadata.cryptographicTrustSnapshotId',
        'cryptographicTrustSnapshotId is required',
      );
    }
    if (projectId.isEmpty) {
      addError(
          'CT_SNAPSHOT_PROJECT', 'metadata.projectId', 'projectId is required');
    }
    if (snapshot.fingerprint.isEmpty) {
      addError(
          'CT_SNAPSHOT_FINGERPRINT', 'fingerprint', 'fingerprint is required');
    }
    if (metadata.fingerprint.isEmpty) {
      addError(
        'CT_SNAPSHOT_METADATA_FINGERPRINT',
        'metadata.fingerprint',
        'metadata fingerprint is required',
      );
    }
    if (metadata.fingerprint != snapshot.fingerprint) {
      addError(
        'CT_SNAPSHOT_FINGERPRINT_MISMATCH',
        'fingerprint',
        'metadata fingerprint does not match snapshot fingerprint',
      );
    }
    if (snapshot.identity != null &&
        snapshot.identity!.snapshotFingerprint != null &&
        snapshot.identity!.snapshotFingerprint != snapshot.fingerprint) {
      addError(
        'CT_SNAPSHOT_IDENTITY_FINGERPRINT',
        'identity.snapshotFingerprint',
        'identity snapshotFingerprint does not match snapshot fingerprint',
      );
    }
    for (final violation in snapshot.projectIdConsistencyViolations()) {
      addError(
        'CT_SNAPSHOT_PROJECT',
        violation.path,
        violation.message,
        relatedId: violation.relatedId,
      );
    }

    final subjectIds = <String>{};
    for (final subject in snapshot.subjects) {
      if (!subjectIds.add(subject.subjectId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_SUBJECT',
          'subjects',
          'duplicate subjectId: ${subject.subjectId}',
          relatedId: subject.subjectId,
        );
      }
      if (subject.subjectId.isEmpty) {
        addError('CT_SNAPSHOT_SUBJECT_ID', 'subjects', 'subjectId is required');
      }
    }

    final digestSubjectIds = <String>{};
    for (final digest in snapshot.digests) {
      if (!digestSubjectIds.add(digest.subjectId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_DIGEST',
          'digests',
          'duplicate digest subjectId: ${digest.subjectId}',
          relatedId: digest.subjectId,
        );
      }
      merge(_digestValidator.validate(digest));
    }

    final keyIds = <String>{};
    for (final keyReference in snapshot.keyReferences) {
      if (!keyIds.add(keyReference.keyId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_KEY',
          'keyReferences',
          'duplicate keyId: ${keyReference.keyId}',
          relatedId: keyReference.keyId,
        );
      }
      merge(_keyReferenceValidator.validate(keyReference));
    }

    final signatureIds = <String>{};
    for (final signature in snapshot.signatures) {
      if (!signatureIds.add(signature.signatureId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_SIGNATURE',
          'signatures',
          'duplicate signatureId: ${signature.signatureId}',
          relatedId: signature.signatureId,
        );
      }
      if (!subjectIds.contains(signature.subject.subjectId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'signatures.${signature.signatureId}.subject.subjectId',
          'signature subjectId not found in subjects: ${signature.subject.subjectId}',
          relatedId: signature.signatureId,
        );
      }
      if (!keyIds.contains(signature.keyReference.keyId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'signatures.${signature.signatureId}.keyReference.keyId',
          'signature keyId not found in keyReferences: ${signature.keyReference.keyId}',
          relatedId: signature.signatureId,
        );
      }
      merge(_signatureEnvelopeValidator.validate(signature));
      if (signature.signerIdentity != null) {
        merge(_signerIdentityValidator.validate(signature.signerIdentity!));
      }
    }

    final attestationIds = <String>{};
    for (final attestation in snapshot.attestations) {
      if (!attestationIds.add(attestation.attestationId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_ATTESTATION',
          'attestations',
          'duplicate attestationId: ${attestation.attestationId}',
          relatedId: attestation.attestationId,
        );
      }
      for (final subject in attestation.subjects) {
        if (!subjectIds.contains(subject.subjectId)) {
          addError(
            'CT_SNAPSHOT_REFERENCE',
            'attestations.${attestation.attestationId}.subjects.${subject.subjectId}',
            'attestation subjectId not found in subjects: ${subject.subjectId}',
            relatedId: attestation.attestationId,
          );
        }
      }
      merge(_attestationValidator.validate(attestation));
    }

    final trustAnchorIds = <String>{};
    for (final anchor in snapshot.trustAnchors) {
      if (!trustAnchorIds.add(anchor.trustAnchorId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_ANCHOR',
          'trustAnchors',
          'duplicate trustAnchorId: ${anchor.trustAnchorId}',
          relatedId: anchor.trustAnchorId,
        );
      }
      if (!keyIds.contains(anchor.keyReference.keyId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'trustAnchors.${anchor.trustAnchorId}.keyReference.keyId',
          'trust anchor keyId not found in keyReferences: ${anchor.keyReference.keyId}',
          relatedId: anchor.trustAnchorId,
        );
      }
      merge(_trustAnchorValidator.validate(anchor));
    }

    final trustChainIds = <String>{};
    for (final chain in snapshot.trustChains) {
      if (!trustChainIds.add(chain.trustChainId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_CHAIN',
          'trustChains',
          'duplicate trustChainId: ${chain.trustChainId}',
          relatedId: chain.trustChainId,
        );
      }
      if (!subjectIds.contains(chain.subjectId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'trustChains.${chain.trustChainId}.subjectId',
          'trust chain subjectId not found in subjects: ${chain.subjectId}',
          relatedId: chain.trustChainId,
        );
      }
      if (!keyIds.contains(chain.leafKey.keyId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'trustChains.${chain.trustChainId}.leafKey.keyId',
          'trust chain leaf keyId not found in keyReferences: ${chain.leafKey.keyId}',
          relatedId: chain.trustChainId,
        );
      }
      if (!trustAnchorIds.contains(chain.trustAnchor.trustAnchorId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'trustChains.${chain.trustChainId}.trustAnchor.trustAnchorId',
          'trust chain trustAnchorId not found in trustAnchors: ${chain.trustAnchor.trustAnchorId}',
          relatedId: chain.trustChainId,
        );
      }
      if (chain.signatureId != null &&
          chain.signatureId!.isNotEmpty &&
          !signatureIds.contains(chain.signatureId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'trustChains.${chain.trustChainId}.signatureId',
          'trust chain signatureId not found in signatures: ${chain.signatureId}',
          relatedId: chain.trustChainId,
        );
      }
      merge(_trustChainValidator.validate(chain));
    }

    final policyIds = <String>{};
    for (final policy in snapshot.trustPolicies) {
      final policyKey = '${policy.policyId}@${policy.version}';
      if (!policyIds.add(policyKey)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_POLICY',
          'trustPolicies',
          'duplicate policy: $policyKey',
          relatedId: policy.policyId,
        );
      }
      merge(_trustPolicyValidator.validate(policy));
      for (final requirement in policy.requirements) {
        merge(_trustRequirementValidator.validate(requirement));
      }
    }

    final requestIds = <String>{};
    for (final request in snapshot.verificationRequests) {
      if (!requestIds.add(request.requestId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_VERIFY_REQUEST',
          'verificationRequests',
          'duplicate requestId: ${request.requestId}',
          relatedId: request.requestId,
        );
      }
      merge(_verificationRequestValidator.validate(request));
    }

    final verificationIds = <String>{};
    for (final result in snapshot.verificationResults) {
      if (!verificationIds.add(result.verificationId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_VERIFY_RESULT',
          'verificationResults',
          'duplicate verificationId: ${result.verificationId}',
          relatedId: result.verificationId,
        );
      }
      if (result.requestId.isNotEmpty &&
          requestIds.isNotEmpty &&
          !requestIds.contains(result.requestId)) {
        addError(
          'CT_SNAPSHOT_REFERENCE',
          'verificationResults.${result.verificationId}.requestId',
          'verification requestId not found in verificationRequests: ${result.requestId}',
          relatedId: result.verificationId,
        );
      }
      merge(_verificationResultValidator.validate(result));
    }

    final revocationIds = <String>{};
    for (final revocation in snapshot.revocations) {
      if (!revocationIds.add(revocation.revocationId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_REVOCATION',
          'revocations',
          'duplicate revocationId: ${revocation.revocationId}',
          relatedId: revocation.revocationId,
        );
      }
      merge(_revocationValidator.validate(revocation));
    }

    final logEntryIds = <String>{};
    for (final logReference in snapshot.transparencyLogReferences) {
      if (!logEntryIds.add(logReference.entryId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_LOG_ENTRY',
          'transparencyLogReferences',
          'duplicate entryId: ${logReference.entryId}',
          relatedId: logReference.entryId,
        );
      }
      merge(_transparencyLogReferenceValidator.validate(logReference));
    }

    final sourceIds = <String>{};
    for (final sourceReference in snapshot.sourceReferences) {
      if (!sourceIds.add(sourceReference.sourceId)) {
        addError(
          'CT_SNAPSHOT_DUPLICATE_SOURCE',
          'sourceReferences',
          'duplicate sourceId: ${sourceReference.sourceId}',
          relatedId: sourceReference.sourceId,
        );
      }
      if (sourceReference.projectId != projectId) {
        addError(
          'CT_SNAPSHOT_PROJECT',
          'sourceReferences.${sourceReference.sourceId}.projectId',
          'source reference projectId mismatch',
          relatedId: sourceReference.sourceId,
        );
      }
    }

    if (snapshot.status == CryptographicTrustStatus.invalid ||
        snapshot.status == CryptographicTrustStatus.revoked) {
      warnings.add('snapshot status is ${snapshot.status.wireName}');
    }

    validateSensitiveMetadata(
      snapshot.metadataMap,
      'metadataMap',
      addError,
      code: 'CT_SNAPSHOT_SENSITIVE_METADATA',
    );

    _validateCrossReferences(snapshot, addError, warnings);

    return buildCryptographicValidationResult(
      issues: issues,
      warnings: warnings,
      errors: errors,
    );
  }

  /// Cross-validates fingerprints, policy results, verification results and status.
  ///
  /// Composes structural validators only — no cryptographic operations.
  void _validateCrossReferences(
    CryptographicTrustSnapshot snapshot,
    void Function(String code, String path, String message, {String? relatedId})
        addError,
    List<String> warnings,
  ) {
    if (snapshot.metadata.releaseId != null &&
        snapshot.verificationResults.any(
          (r) =>
              r.releaseId != null && r.releaseId != snapshot.metadata.releaseId,
        )) {
      addError(
        'CT_SNAPSHOT_RELEASE',
        'verificationResults.releaseId',
        'verification result releaseId mismatch',
      );
    }

    for (final result in snapshot.verificationResults) {
      for (final policyResult in result.policyResults) {
        if (!snapshot.trustPolicies
            .any((p) => p.policyId == policyResult.policyId)) {
          addError(
            'CT_SNAPSHOT_REFERENCE',
            'verificationResults.${result.verificationId}.policyResults.${policyResult.policyId}',
            'policy result references unknown policy',
            relatedId: result.verificationId,
          );
        }
        if (policyResult.metadata.containsKey('releaseAuthorized') ||
            policyResult.metadata.containsKey('deploymentAuthorized')) {
          addError(
            'CT_SNAPSHOT_FORBIDDEN_FIELD',
            'verificationResults.${result.verificationId}.policyResults.${policyResult.policyId}.metadata',
            'forbidden authorization field in policy result metadata',
            relatedId: policyResult.policyId,
          );
        }
      }

      if (result.status == CryptographicVerificationStatus.verified) {
        warnings.add(
          'verification ${result.verificationId} verified — does not authorize release',
        );
      }
    }

    for (final chain in snapshot.trustChains) {
      if (chain.status == CryptographicTrustStatus.trusted) {
        warnings.add(
          'trust chain ${chain.trustChainId} trusted — declarative only',
        );
      }
    }

    if (snapshot.identity != null) {
      if (snapshot.identity!.snapshotFingerprint != snapshot.fingerprint) {
        addError(
          'CT_SNAPSHOT_IDENTITY_FINGERPRINT',
          'identity.snapshotFingerprint',
          'identity snapshotFingerprint does not match snapshot fingerprint',
        );
      }

      final computedFingerprint =
          _serializer.snapshotContentFingerprint(snapshot);
      if (computedFingerprint != snapshot.fingerprint) {
        addError(
          'CT_SNAPSHOT_FINGERPRINT_REPLAY',
          'fingerprint',
          'snapshot fingerprint does not match canonical replay',
        );
      }

      if (snapshot.metadata.subjectsFingerprint != null &&
          snapshot.subjects.isNotEmpty) {
        final material = CollectedCryptographicTrustMaterial(
          subjects: snapshot.subjects,
        );
        final computedSubjects = _identityBuilder.subjectsFingerprint(material);
        if (computedSubjects.isNotEmpty &&
            computedSubjects != snapshot.metadata.subjectsFingerprint) {
          addError(
            'CT_SNAPSHOT_SUBJECTS_FINGERPRINT',
            'metadata.subjectsFingerprint',
            'subjects fingerprint mismatch',
          );
        }
      }
    }
  }
}

extension _CryptographicTrustSnapshotProjectChecks
    on CryptographicTrustSnapshot {
  Iterable<_ProjectViolation> projectIdConsistencyViolations() sync* {
    final expectedProjectId = metadata.projectId;
    if (expectedProjectId.isEmpty) return;

    for (final subject in subjects) {
      if (subject.projectId != expectedProjectId) {
        yield _ProjectViolation(
          path: 'subjects.${subject.subjectId}.projectId',
          message: 'subject projectId mismatch',
          relatedId: subject.subjectId,
        );
      }
    }
    for (final attestation in attestations) {
      for (final subject in attestation.subjects) {
        if (subject.projectId != expectedProjectId) {
          yield _ProjectViolation(
            path:
                'attestations.${attestation.attestationId}.subjects.${subject.subjectId}.projectId',
            message: 'attestation subject projectId mismatch',
            relatedId: attestation.attestationId,
          );
        }
      }
    }
    for (final request in verificationRequests) {
      if (request.projectId != expectedProjectId) {
        yield _ProjectViolation(
          path: 'verificationRequests.${request.requestId}.projectId',
          message: 'verification request projectId mismatch',
          relatedId: request.requestId,
        );
      }
    }
    for (final result in verificationResults) {
      if (result.projectId != expectedProjectId) {
        yield _ProjectViolation(
          path: 'verificationResults.${result.verificationId}.projectId',
          message: 'verification result projectId mismatch',
          relatedId: result.verificationId,
        );
      }
    }
  }
}

class _ProjectViolation {
  const _ProjectViolation({
    required this.path,
    required this.message,
    this.relatedId,
  });

  final String path;
  final String message;
  final String? relatedId;
}
