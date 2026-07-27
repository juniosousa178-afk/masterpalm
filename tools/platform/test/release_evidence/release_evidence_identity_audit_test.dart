import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_canonical_serializer.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_identity_builder.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence identity audit', () {
    const serializer = ReleaseEvidenceCanonicalSerializer();
    const identity = ReleaseEvidenceIdentityBuilder();

    test('bundle fingerprint excludes bundleId and temporal metadata', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final fp1 = serializer.bundleFingerprint(bundle);
      final mutated = bundle.copyWith(
        metadata: bundle.metadata.copyWith(
          createdAt: '2099-01-01T00:00:00.000Z',
          evaluatedAt: '2099-01-01T00:00:00.000Z',
        ),
      );
      expect(serializer.bundleFingerprint(mutated), fp1);
    });

    test('bundle fingerprint changes when normative evidence changes', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final fp1 = serializer.bundleFingerprint(bundle);
      final mutated = bundle.copyWith(
        metadata: bundle.metadata.copyWith(evidenceCount: 99),
      );
      expect(serializer.bundleFingerprint(mutated), isNot(fp1));
    });

    test('bundleId includes normative fingerprint components', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final id = identity.buildBundleIdFromBundle(bundle);
      expect(id, contains(bundle.metadata.projectId));
      expect(id, contains(bundle.metadata.releaseId));
      expect(id, contains(bundle.metadata.policyId));
      expect(id, contains(bundle.fingerprint));
    });

    test('verification fingerprint is stable for same normative content', () {
      final result = ReleaseEvidenceTestFixtures.validVerificationResult();
      final fp1 = serializer.verificationFingerprint(result);
      final fp2 = serializer.verificationFingerprint(result);
      expect(fp1, fp2);
      expect(fp1, isNotEmpty);
    });

    test('verificationId includes policy and fingerprint', () {
      final result = ReleaseEvidenceTestFixtures.validVerificationResult();
      final id = identity.buildVerificationIdFromResult(result);
      expect(id, startsWith('release-verification:'));
      expect(id, contains(result.policyReference.policyId));
      expect(id, contains(result.fingerprint));
    });

    test('attestation fingerprint excludes attestationId and createdAt', () {
      final attestation = ReleaseEvidenceTestFixtures.validAttestation();
      final fp1 = serializer.attestationFingerprint(attestation);
      final json = attestation.toJson();
      final metadata = Map<String, dynamic>.from(json['metadata'] as Map);
      metadata['createdAt'] = '2099-01-01T00:00:00.000Z';
      metadata['attestationId'] = 'different-id';
      json['metadata'] = metadata;
      final restored =
          ReleaseEvidenceTestFixtures.validAttestation(); // same normative
      expect(serializer.attestationFingerprint(restored), fp1);
    });

    test('identity builder fingerprintForBundle matches serializer', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      expect(
        identity.fingerprintForBundle(bundle),
        serializer.bundleFingerprint(bundle),
      );
    });
  });
}
