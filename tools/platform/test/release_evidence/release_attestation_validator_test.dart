import 'package:masterpalm_platform/models/release_evidence/release_attestation.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_attestation_policy_validator.dart';
import 'package:masterpalm_platform/release_evidence/release_attestation_validator.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  const policyValidator = ReleaseAttestationPolicyValidator();
  const attestationValidator = ReleaseAttestationValidator();

  group('ReleaseAttestationPolicyValidator', () {
    test('valid candidate policy passes', () {
      final result =
          policyValidator.validate(ReleaseAttestationPolicyV1.create());
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('incoherent signature policy fails', () {
      final base = ReleaseAttestationPolicyV1.create();
      final policy = ReleaseAttestationPolicy(
        metadata: base.metadata,
        supportedAttestationTypes: base.supportedAttestationTypes,
        supportedPredicateTypes: base.supportedPredicateTypes,
        issuerRequirements: base.issuerRequirements,
        authorityRequirements: base.authorityRequirements,
        evidenceRequirements: base.evidenceRequirements,
        subjectRequirements: base.subjectRequirements,
        expirationPolicy: base.expirationPolicy,
        signaturePolicy: const ReleaseAttestationSignaturePolicy(
          signatureRequired: true,
          allowAbsentSignature: true,
          futureCapabilityOnly: false,
        ),
        compatibilityPolicy: base.compatibilityPolicy,
        requiredAttestations: base.requiredAttestations,
      );
      expect(policyValidator.validate(policy).isValid, isFalse);
    });
  });

  group('ReleaseAttestationValidator', () {
    test('valid attestation passes', () {
      final result = attestationValidator.validate(
        ReleaseEvidenceTestFixtures.validAttestation(),
        policy: ReleaseAttestationPolicyV1.create(),
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
        expectedProjectId: ReleaseEvidenceTestFixtures.projectId,
      );
      expect(result.isValid, isTrue, reason: result.errors.join('; '));
    });

    test('missing subject fails', () {
      final base = ReleaseEvidenceTestFixtures.validAttestation();
      final attestation = ReleaseAttestation(
        metadata: base.metadata,
        statement: base.statement,
        subjects: const [],
        predicate: base.predicate,
        issuer: base.issuer,
        authority: base.authority,
        status: base.status,
        issuedAt: base.issuedAt,
        validFrom: base.validFrom,
        evidenceReferences: base.evidenceReferences,
        fingerprint: base.fingerprint,
        schemaVersion: base.schemaVersion,
      );
      expect(attestationValidator.validate(attestation).isValid, isFalse);
    });

    test('expired attestation warns', () {
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
        expiresAt: '2020-01-01T00:00:00.000Z',
        evidenceReferences: base.evidenceReferences,
        fingerprint: base.fingerprint,
        schemaVersion: base.schemaVersion,
      );
      final result = attestationValidator.validate(
        attestation,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      expect(result.warnings.any((w) => w.contains('expired')), isTrue);
    });

    test('authorization contradicting rejected release fails', () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation(
        type: ReleaseAttestationType.releaseAuthorization,
        predicateType: ReleaseAttestationPredicateType.readiness,
        outcome: 'approved',
        authorizationConsistent: true,
      );
      final result = attestationValidator.validate(
        attestation,
        releaseGovernanceDecision: ReleaseGovernanceDecision.rejected.wireName,
      );
      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('rejected release')),
        isTrue,
      );
    });
  });
}
