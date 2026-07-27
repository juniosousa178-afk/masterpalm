import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_attestation_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_key_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_revocation_record.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_signature_envelope.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_signer_identity.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_transparency_log_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_algorithm_descriptors.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_anchor.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_chain.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_digest.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_fingerprint.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_identity.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_requirement.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_snapshot.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_source_reference.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_subject.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_validation_result.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_verification_models.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/collected_cryptographic_trust_material.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_identity_builder.dart';

/// Shared fixtures for Cryptographic Trust domain tests.
class CryptographicTrustTestFixtures {
  static const projectId = 'masterpalm-demo';
  static const referenceTime = '2026-07-22T12:00:00.000Z';
  static const sha256Placeholder =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  static const releaseId = 'rel-2026-07-22-001';

  static CryptographicDigestDescriptor validDigestDescriptor() {
    return const CryptographicDigestDescriptor(
      algorithm: CryptographicDigestAlgorithm.sha256,
      algorithmId: 'sha256-v1',
      outputSizeBits: 256,
      parameters: {'domain': 'cryptographic-trust'},
    );
  }

  static CryptographicSignatureDescriptor validSignatureDescriptor() {
    return const CryptographicSignatureDescriptor(
      algorithm: CryptographicSignatureAlgorithm.ed25519,
      algorithmId: 'ed25519-v1',
      keyType: CryptographicKeyType.ed25519,
      format: CryptographicSignatureFormat.raw,
    );
  }

  static CryptographicDigest validDigest(
      {String subjectId = 'subject-art-001'}) {
    return CryptographicDigest(
      descriptor: validDigestDescriptor(),
      value: sha256Placeholder,
      encoding: 'hex',
      subjectId: subjectId,
      createdAt: referenceTime,
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicKeyReference validKeyReference({
    String keyId = 'key-signer-001',
  }) {
    return CryptographicKeyReference(
      keyId: keyId,
      keyType: CryptographicKeyType.ed25519,
      algorithmId: 'ed25519-v1',
      usage: const [
        CryptographicKeyUsage.sign,
        CryptographicKeyUsage.verify,
      ],
      status: CryptographicKeyStatus.active,
      publicKeyFingerprint: sha256Placeholder,
      version: '1',
      validFrom: '2026-01-01T00:00:00.000Z',
      validUntil: '2027-01-01T00:00:00.000Z',
      metadata: const {'owner': 'platform-team'},
    );
  }

  static CryptographicTrustSubject validSubject() {
    return CryptographicTrustSubject(
      subjectId: 'subject-art-001',
      subjectType: CryptographicTrustSubjectType.artifact,
      projectId: projectId,
      releaseId: releaseId,
      artifactId: 'art-apk-001',
      artifactType: 'binary',
      sourceModule: 'release-supply-chain',
      sourceFingerprint: sha256Placeholder,
      digest: validDigest(),
      metadata: const {'channel': 'staging'},
    );
  }

  static CryptographicSignerIdentity validSignerIdentity() {
    return CryptographicSignerIdentity(
      identityId: 'signer-001',
      identityType: CryptographicIdentityType.service,
      displayName: 'Release Signing Service',
      organizationId: 'org-masterpalm',
      keyId: 'key-signer-001',
      trustLevel: CryptographicTrustLevel.high,
      claims: const {'role': 'release-signer'},
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicTrustAnchorReference validTrustAnchorReference() {
    return CryptographicTrustAnchorReference(
      trustAnchorId: 'anchor-root-001',
      keyReference: validKeyReference(keyId: 'key-anchor-001'),
      trustLevel: CryptographicTrustLevel.critical,
      status: CryptographicTrustStatus.trusted,
      issuer: 'MasterPalm Root CA',
      scope: const {'domain': 'cryptographic-trust'},
      validFrom: '2026-01-01T00:00:00.000Z',
      validUntil: '2028-01-01T00:00:00.000Z',
    );
  }

  static CryptographicSignatureEnvelope validSignatureEnvelope() {
    final subject = validSubject();
    return CryptographicSignatureEnvelope(
      signatureId: 'sig-art-001',
      subject: subject,
      subjectDigest: validDigest(subjectId: subject.subjectId),
      signatureDescriptor: validSignatureDescriptor(),
      signatureValue: 'dGVzdC1zaWduYXR1cmU=',
      signatureEncoding: 'base64',
      keyReference: validKeyReference(),
      signerIdentity: validSignerIdentity(),
      signedAt: referenceTime,
      expiresAt: '2027-07-22T12:00:00.000Z',
      trustAnchorReference: validTrustAnchorReference(),
      sourceReferences: const [
        {'sourceId': 'src-evidence-001', 'module': 'release-evidence'},
      ],
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicAttestationSubject validAttestationSubject() {
    return CryptographicAttestationSubject(
      subjectId: 'subject-art-001',
      subjectType: CryptographicTrustSubjectType.artifact,
      subjectFingerprint: sha256Placeholder,
      digest: validDigest(),
      projectId: projectId,
      releaseId: releaseId,
      artifactId: 'art-apk-001',
      metadata: const {'kind': 'release-artifact'},
    );
  }

  static CryptographicAttestationPredicate validAttestationPredicate() {
    return CryptographicAttestationPredicate(
      predicateType: 'buildProvenance',
      schemaVersion: 1,
      claims: const {'builder': 'ci-pipeline'},
      sourceReferences: [validSourceReference()],
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicAttestationStatement validAttestationStatement() {
    return CryptographicAttestationStatement(
      attestationId: 'att-provenance-001',
      attestationType: CryptographicAttestationType.buildProvenance,
      schemaVersion: 1,
      subjects: [validAttestationSubject()],
      predicate: validAttestationPredicate(),
      issuerIdentity: validSignerIdentity(),
      issuedAt: referenceTime,
      expiresAt: '2027-07-22T12:00:00.000Z',
      signatures: [validSignatureEnvelope()],
      status: CryptographicAttestationStatus.issued,
      sourceReferences: [validSourceReference()],
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicRevocationRecord validRevocationRecord() {
    return CryptographicRevocationRecord(
      revocationId: 'rev-key-001',
      subjectType: CryptographicTrustSubjectType.key,
      subjectId: 'key-signer-001',
      status: CryptographicRevocationStatus.active,
      reasonCode: 'keyCompromise',
      reason: 'Key rotated proactively',
      revokedAt: referenceTime,
      effectiveAt: referenceTime,
      issuerIdentity: validSignerIdentity(),
      sourceReferences: [validSourceReference()],
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicTransparencyLogReference validTransparencyLogReference() {
    return CryptographicTransparencyLogReference(
      logId: 'rekor-log-001',
      entryId: 'entry-001',
      logType: 'rekor',
      status: CryptographicTransparencyLogStatus.integrated,
      integratedTime: referenceTime,
      entryDigest: validDigest(subjectId: 'log-entry-001'),
      inclusionProofReference: 'proof-ref-001',
      checkpointReference: 'checkpoint-ref-001',
      sourceReferences: [validSourceReference()],
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicTrustRequirement validRequirement() {
    return const CryptographicTrustRequirement(
      requirementId: 'require-artifact-signature',
      requirementType: CryptographicRequirementType.signature,
      required: true,
      minimumTrustLevel: CryptographicTrustLevel.moderate,
      allowedAlgorithms: [
        CryptographicSignatureAlgorithm.ed25519,
        CryptographicSignatureAlgorithm.ecdsa,
      ],
      allowedKeyTypes: [
        CryptographicKeyType.ed25519,
        CryptographicKeyType.ec,
      ],
      requiredKeyUsage: [
        CryptographicKeyUsage.sign,
        CryptographicKeyUsage.verify,
      ],
      requiredSignatureCount: 1,
      requireTrustAnchor: true,
      requireNonRevokedKey: true,
    );
  }

  static CryptographicTrustPolicy validPolicy() {
    return CryptographicTrustPolicy(
      policyId: 'test-policy-001',
      version: 1,
      name: 'Structural Test Policy',
      description: 'Policy fixture for cryptographic trust validation tests.',
      status: CryptographicPolicyStatus.candidate,
      requirements: [validRequirement()],
      trustAnchors: [validTrustAnchorReference()],
      scope: const {
        'domain': 'cryptographic-trust',
        'subjectType': 'artifact',
      },
      createdAt: referenceTime,
      metadata: const {'limitations': 'structural-descriptor-only'},
    );
  }

  static CryptographicTrustPolicy factoryArtifactSignaturePolicy() {
    return ArtifactSignatureTrustPolicyV1.create();
  }

  static CryptographicTrustChain validTrustChain() {
    return CryptographicTrustChain(
      trustChainId: 'chain-art-001',
      subjectId: 'subject-art-001',
      signatureId: 'sig-art-001',
      leafKey: validKeyReference(),
      intermediateReferences: [
        validKeyReference(keyId: 'key-intermediate-001'),
      ],
      trustAnchor: validTrustAnchorReference(),
      status: CryptographicTrustStatus.provisional,
      issues: const [
        CryptographicVerificationIssue(
          code: 'CT_CHAIN_STRUCTURAL',
          severity: CryptographicIssueSeverity.info,
          path: 'trustChain',
          message: 'Structural chain descriptor only',
        ),
      ],
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicTrustSourceReference validSourceReference() {
    return const CryptographicTrustSourceReference(
      sourceType: CryptographicSourceType.releaseEvidence,
      sourceId: 'src-evidence-001',
      projectId: projectId,
      releaseId: releaseId,
      fingerprint: sha256Placeholder,
      version: 1,
      metadata: {'module': 'release-evidence'},
    );
  }

  static CryptographicVerificationRequest validVerificationRequest() {
    return CryptographicVerificationRequest(
      requestId: 'verify-req-001',
      projectId: projectId,
      releaseId: releaseId,
      subjects: [validSubject()],
      signatures: [validSignatureEnvelope()],
      attestations: [validAttestationStatement()],
      policy: validPolicy(),
      trustAnchors: [validTrustAnchorReference()],
      revocations: [validRevocationRecord()],
      transparencyLogReferences: [validTransparencyLogReference()],
      requestedAt: referenceTime,
      metadata: const {'projectId': projectId},
    );
  }

  static CryptographicVerificationResult validVerificationResult() {
    return CryptographicVerificationResult(
      verificationId: 'verify-result-001',
      requestId: 'verify-req-001',
      projectId: projectId,
      releaseId: releaseId,
      status: CryptographicVerificationStatus.verified,
      trustLevel: CryptographicTrustLevel.high,
      subjectResults: const [
        CryptographicSubjectVerificationResult(
          subjectId: 'subject-art-001',
          status: CryptographicVerificationStatus.verified,
          trustLevel: CryptographicTrustLevel.high,
        ),
      ],
      signatureResults: const [
        CryptographicSignatureVerificationResult(
          signatureId: 'sig-art-001',
          status: CryptographicVerificationStatus.verified,
          trustLevel: CryptographicTrustLevel.high,
        ),
      ],
      attestationResults: const [
        CryptographicAttestationVerificationResult(
          attestationId: 'att-provenance-001',
          status: CryptographicVerificationStatus.verified,
          trustLevel: CryptographicTrustLevel.moderate,
        ),
      ],
      policyResults: const [
        CryptographicPolicyVerificationResult(
          policyId: 'test-policy-001',
          status: CryptographicVerificationStatus.partiallyVerified,
          trustLevel: CryptographicTrustLevel.moderate,
          satisfiedRequirementIds: ['require-artifact-signature'],
        ),
      ],
      verifiedAt: referenceTime,
      metadata: const {
        'limitations': 'no-release-authorization,structural-descriptor-only',
      },
    );
  }

  static CryptographicTrustSnapshotMetadata validSnapshotMetadata({
    required String fingerprint,
  }) {
    return CryptographicTrustSnapshotMetadata(
      cryptographicTrustSnapshotId: 'ct-snap-001',
      projectId: projectId,
      releaseId: releaseId,
      schemaVersion: CryptographicTrustSnapshotMetadata.currentSchemaVersion,
      canonicalizationVersion:
          CryptographicTrustSnapshotMetadata.currentCanonicalizationVersion,
      createdAt: referenceTime,
      evaluatedAt: referenceTime,
      fingerprint: fingerprint,
      status: CryptographicTrustStatus.provisional,
      subjectsFingerprint: sha256Placeholder,
      signaturesFingerprint: sha256Placeholder,
      limitations: const [
        'no-real-signature-verification',
        'no-release-authorization',
        'structural-descriptor-only',
      ],
    );
  }

  static CryptographicTrustIdentity validIdentity(
      {required String fingerprint}) {
    return CryptographicTrustIdentity(
      cryptographicTrustId: 'ct-identity-001',
      subjectsFingerprint: sha256Placeholder,
      signaturesFingerprint: sha256Placeholder,
      attestationsFingerprint: sha256Placeholder,
      policiesFingerprint: sha256Placeholder,
      trustChainsFingerprint: sha256Placeholder,
      verificationFingerprint: sha256Placeholder,
      snapshotFingerprint: fingerprint,
    );
  }

  static CryptographicTrustSnapshot validSnapshot() {
    const identityBuilder = CryptographicTrustIdentityBuilder();
    final body = CryptographicTrustSnapshot(
      metadata: CryptographicTrustSnapshotMetadata(
        cryptographicTrustSnapshotId: 'ct-snap-001',
        projectId: projectId,
        releaseId: releaseId,
        schemaVersion: CryptographicTrustSnapshotMetadata.currentSchemaVersion,
        canonicalizationVersion:
            CryptographicTrustSnapshotMetadata.currentCanonicalizationVersion,
        createdAt: referenceTime,
        evaluatedAt: referenceTime,
        fingerprint: sha256Placeholder,
        status: CryptographicTrustStatus.provisional,
        limitations: const [
          'no-real-signature-verification',
          'no-release-authorization',
          'structural-descriptor-only',
        ],
      ),
      fingerprint: sha256Placeholder,
      status: CryptographicTrustStatus.provisional,
      subjects: [validSubject()],
      digests: [validDigest()],
      keyReferences: [
        validKeyReference(),
        validKeyReference(keyId: 'key-anchor-001'),
        validKeyReference(keyId: 'key-intermediate-001'),
      ],
      signatures: [validSignatureEnvelope()],
      attestations: [validAttestationStatement()],
      trustAnchors: [validTrustAnchorReference()],
      trustChains: [validTrustChain()],
      trustPolicies: [validPolicy()],
      verificationRequests: [validVerificationRequest()],
      verificationResults: [validVerificationResult()],
      revocations: [validRevocationRecord()],
      transparencyLogReferences: [validTransparencyLogReference()],
      sourceReferences: [validSourceReference()],
      warnings: const ['structural-descriptor-only'],
      limitations: const [
        'no-real-signature-verification',
        'no-release-authorization',
        'structural-descriptor-only',
      ],
      metadataMap: const {'projectId': projectId},
    );

    final material = CollectedCryptographicTrustMaterial(
      subjects: body.subjects,
      digests: body.digests,
      keyReferences: body.keyReferences,
      signatures: body.signatures,
      attestations: body.attestations,
      trustAnchors: body.trustAnchors,
      trustChains: body.trustChains,
      policies: body.trustPolicies,
      verificationRequests: body.verificationRequests,
      revocations: body.revocations,
      transparencyLogReferences: body.transparencyLogReferences,
      sourceReferences: body.sourceReferences,
    );

    final subjectsFp = identityBuilder.subjectsFingerprint(material);
    final signaturesFp = identityBuilder.signaturesFingerprint(material);
    final attestationsFp = identityBuilder.attestationsFingerprint(material);
    final policiesFp = identityBuilder.policiesFingerprint(material);
    final chainsFp = identityBuilder.trustChainsFingerprint(material);
    final verificationFp = identityBuilder
        .verificationFingerprintForResult(validVerificationResult());

    final staged = body.copyWith(
      metadata: body.metadata.copyWith(
        subjectsFingerprint: subjectsFp.isEmpty ? null : subjectsFp,
        signaturesFingerprint: signaturesFp.isEmpty ? null : signaturesFp,
        attestationsFingerprint: attestationsFp.isEmpty ? null : attestationsFp,
        policiesFingerprint: policiesFp.isEmpty ? null : policiesFp,
        trustChainsFingerprint: chainsFp.isEmpty ? null : chainsFp,
        verificationFingerprint: verificationFp,
      ),
    );

    final fingerprint = identityBuilder.fingerprintForSnapshot(staged);
    final identity = identityBuilder.buildIdentity(
      snapshot: staged.copyWith(fingerprint: fingerprint),
      material: material,
      verificationResult: validVerificationResult(),
    );
    final metadata = staged.metadata.copyWith(fingerprint: fingerprint);

    return staged.copyWith(
      metadata: metadata,
      fingerprint: fingerprint,
      identity: identity,
    );
  }

  static CryptographicValidationIssue validValidationIssue() {
    return const CryptographicValidationIssue(
      code: 'CT_SAMPLE',
      path: 'sample.path',
      severity: CryptographicIssueSeverity.warning,
      message: 'Sample validation issue',
      relatedId: 'sample-001',
    );
  }

  static CryptographicValidationResult validValidationResult() {
    return CryptographicValidationResult(
      isValid: false,
      issues: [validValidationIssue()],
      warnings: const ['sample warning'],
      errors: const ['sample error'],
    );
  }
}
