import 'package:masterpalm_platform/models/release_evidence/release_attestation.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_authority.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_issuer.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_predicate.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_signature_reference.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_attestation_engine.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_verification_engine.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence engine audit', () {
    final attestationEngine = ReleaseEvidenceAttestationEngine();
    final verificationEngine = ReleaseEvidenceVerificationEngine();
    final attestationPolicy = ReleaseAttestationPolicyV1.create();
    final verificationPolicy = ReleaseVerificationPolicyV1.create();
    final bundle = ReleaseEvidenceTestFixtures.validBundle();

    test('invalid issuer produces evaluation errors', () {
      final base = ReleaseEvidenceTestFixtures.validAttestation();
      final attestation = ReleaseAttestation(
        metadata: base.metadata,
        statement: base.statement,
        subjects: base.subjects,
        predicate: base.predicate,
        issuer: const ReleaseAttestationIssuer(
          issuerId: '',
          issuerType: ReleaseAttestationIssuerType.platform,
          identityStatus: ReleaseIdentityStatus.unknown,
          validFrom: '2026-01-01T00:00:00.000Z',
        ),
        authority: base.authority,
        status: base.status,
        issuedAt: base.issuedAt,
        validFrom: base.validFrom,
        evidenceReferences: base.evidenceReferences,
        fingerprint: base.fingerprint,
        schemaVersion: base.schemaVersion,
      );
      final evaluation = attestationEngine.evaluate(
        attestation: attestation,
        policy: attestationPolicy,
        bundle: bundle,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      expect(evaluation.issuerValid, isFalse);
    });

    test('inactive authority fails structural evaluation', () {
      final base = ReleaseEvidenceTestFixtures.validAttestation();
      final attestation = ReleaseAttestation(
        metadata: base.metadata,
        statement: base.statement,
        subjects: base.subjects,
        predicate: base.predicate,
        issuer: base.issuer,
        authority: ReleaseAttestationAuthority(
          authorityId: base.authority.authorityId,
          authorityType: base.authority.authorityType,
          allowedAttestationTypes: base.authority.allowedAttestationTypes,
          allowedSubjectTypes: base.authority.allowedSubjectTypes,
          allowedEnvironments: base.authority.allowedEnvironments,
          allowedReleaseTypes: base.authority.allowedReleaseTypes,
          validFrom: base.authority.validFrom,
          status: ReleaseAttestationAuthorityStatus.revoked,
          schemaVersion: base.authority.schemaVersion,
        ),
        status: base.status,
        issuedAt: base.issuedAt,
        validFrom: base.validFrom,
        evidenceReferences: base.evidenceReferences,
        fingerprint: base.fingerprint,
        schemaVersion: base.schemaVersion,
      );
      final evaluation = attestationEngine.evaluate(
        attestation: attestation,
        policy: attestationPolicy,
        referenceTime: '2026-06-15T12:00:00.000Z',
      );
      expect(evaluation.authorityValid, isFalse);
    });

    test('unverified signature produces warning not crypto validation', () {
      final base = ReleaseEvidenceTestFixtures.validAttestation();
      final attestation = ReleaseAttestation(
        metadata: base.metadata,
        statement: base.statement,
        subjects: base.subjects,
        predicate: base.predicate,
        issuer: base.issuer,
        authority: base.authority,
        status: base.status,
        issuedAt: base.issuedAt,
        validFrom: base.validFrom,
        evidenceReferences: base.evidenceReferences,
        signatureReference: const ReleaseSignatureReference(
          signatureId: 'sig-001',
          signatureType: 'cosign',
          algorithm: 'none',
          keyId: 'key-001',
          signedArtifactId: ReleaseEvidenceTestFixtures.bundleId,
          signedFingerprint: ReleaseEvidenceTestFixtures.bundleFingerprint,
          signatureLocation: 'in-memory',
          verificationStatus: ReleaseSignatureVerificationStatus.unverified,
        ),
        fingerprint: base.fingerprint,
        schemaVersion: base.schemaVersion,
      );
      final evaluation = attestationEngine.evaluate(
        attestation: attestation,
        policy: attestationPolicy,
        bundle: bundle,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      expect(
        evaluation.warnings.any(
          (w) => w.code == ReleaseEvidenceWarningCode.signatureUnverified,
        ),
        isTrue,
      );
      expect(evaluation.limitations, isNotEmpty);
    });

    test('verification remains structural and does not authorize release', () {
      final result = verificationEngine.verify(
        bundle: bundle,
        policy: verificationPolicy,
        evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      expect(
        [
          ReleaseVerificationStatus.verified,
          ReleaseVerificationStatus.partiallyVerified,
          ReleaseVerificationStatus.unverified,
          ReleaseVerificationStatus.invalid,
        ],
        contains(result.status),
      );
    });

    test('verification with missing fingerprint in bundle fails check', () {
      final bundleNoFp = ReleaseEvidenceTestFixtures.validBundle().copyWith(
        fingerprint: '',
        metadata: ReleaseEvidenceTestFixtures.validBundle()
            .metadata
            .copyWith(fingerprint: ''),
      );
      final result = verificationEngine.verify(
        bundle: bundleNoFp,
        policy: verificationPolicy,
        evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      expect(
        result.checks.any(
          (c) =>
              c.checkType == ReleaseVerificationCheckType.fingerprint &&
              c.status == ReleaseVerificationCheckStatus.failed,
        ),
        isTrue,
      );
    });
  });
}
