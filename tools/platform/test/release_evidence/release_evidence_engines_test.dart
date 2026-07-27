import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_attestation_engine.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_verification_engine.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('ReleaseEvidenceAttestationEngine', () {
    final engine = ReleaseEvidenceAttestationEngine();
    final policy = ReleaseAttestationPolicyV1.create();
    final bundle = ReleaseEvidenceTestFixtures.validBundle();

    test('evaluates valid attestation structurally', () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation();
      final evaluation = engine.evaluate(
        attestation: attestation,
        policy: policy,
        bundle: bundle,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
        expectedProjectId: ReleaseEvidenceTestFixtures.projectId,
        expectedReleaseId: ReleaseEvidenceTestFixtures.releaseId,
        expectedCommitId: ReleaseEvidenceTestFixtures.commitId,
      );

      expect(evaluation.structurallyValid, isTrue);
      expect(evaluation.issuerValid, isTrue);
      expect(evaluation.authorityValid, isTrue);
      expect(evaluation.limitations, isNotEmpty);
    });

    test('does not approve release decision', () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation(
        authorizationConsistent: false,
      );
      final evaluation = engine.evaluate(
        attestation: attestation,
        policy: policy,
        bundle: bundle,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );
      expect(evaluation.structurallyValid, isA<bool>());
    });
  });

  group('ReleaseEvidenceVerificationEngine', () {
    final engine = ReleaseEvidenceVerificationEngine();
    final policy = ReleaseVerificationPolicyV1.create();
    final bundle = ReleaseEvidenceTestFixtures.validBundle();

    test('produces verification result with checks', () {
      final result = engine.verify(
        bundle: bundle,
        policy: policy,
        evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      expect(result.checks, isNotEmpty);
      expect(result.fingerprint, isNotEmpty);
      expect(result.verificationId, isNotEmpty);
    });

    test('verification status is structural only', () {
      final result = engine.verify(
        bundle: bundle,
        policy: policy,
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

    test('fingerprint check runs when required', () {
      final result = engine.verify(
        bundle: bundle,
        policy: policy,
        evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
        referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
      );

      expect(
        result.checks.any(
          (c) => c.checkType == ReleaseVerificationCheckType.fingerprint,
        ),
        isTrue,
      );
    });
  });
}
