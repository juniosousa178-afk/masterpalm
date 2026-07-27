import 'package:masterpalm_platform/models/release_evidence/release_attestation.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_attestation_set.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_request.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/release_evidence/release_provenance.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_policy.dart';
import 'package:masterpalm_platform/models/release_evidence/release_verification_result.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence serialization audit', () {
    void roundTrip<T>({
      required T original,
      required Map<String, dynamic> Function(T) toJson,
      required T Function(Map<String, dynamic>) fromJson,
      void Function(T restored)? assertEqual,
    }) {
      final json = toJson(original);
      final restored = fromJson(Map<String, dynamic>.from(json));
      assertEqual?.call(restored);
    }

    test('ReleaseEvidenceBundle roundtrip', () {
      roundTrip<ReleaseEvidenceBundle>(
        original: ReleaseEvidenceTestFixtures.validBundle(),
        toJson: (b) => b.toJson(),
        fromJson: ReleaseEvidenceBundle.fromJson,
        assertEqual: (r) {
          expect(r.metadata.bundleId,
              ReleaseEvidenceTestFixtures.validBundle().metadata.bundleId);
          expect(r.fingerprint, ReleaseEvidenceTestFixtures.bundleFingerprint);
        },
      );
    });

    test('ReleaseVerificationResult roundtrip', () {
      roundTrip<ReleaseVerificationResult>(
        original: ReleaseEvidenceTestFixtures.validVerificationResult(),
        toJson: (v) => v.toJson(),
        fromJson: ReleaseVerificationResult.fromJson,
        assertEqual: (r) =>
            expect(r.status, ReleaseVerificationStatus.verified),
      );
    });

    test('ReleaseAttestationSet roundtrip', () {
      roundTrip<ReleaseAttestationSet>(
        original: ReleaseEvidenceTestFixtures.validAttestationSet(),
        toJson: (s) => s.toJson(),
        fromJson: ReleaseAttestationSet.fromJson,
        assertEqual: (r) => expect(r.attestations, hasLength(1)),
      );
    });

    test('ReleaseAttestation roundtrip', () {
      roundTrip<ReleaseAttestation>(
        original: ReleaseEvidenceTestFixtures.validAttestation(),
        toJson: (a) => a.toJson(),
        fromJson: ReleaseAttestation.fromJson,
        assertEqual: (r) => expect(r.metadata.attestationType,
            ReleaseAttestationType.evidenceBundleIntegrity),
      );
    });

    test('ReleaseProvenance roundtrip', () {
      roundTrip<ReleaseProvenance>(
        original: ReleaseEvidenceTestFixtures.validProvenance(),
        toJson: (p) => p.toJson(),
        fromJson: ReleaseProvenance.fromJson,
        assertEqual: (r) => expect(r.steps, hasLength(1)),
      );
    });

    test('ReleaseEvidenceRequest roundtrip preserves useLatest', () {
      final request =
          ReleaseEvidenceTestFixtures.passingRequest(useLatest: true);
      final json = request.toJson();
      final restored = ReleaseEvidenceRequest.fromJson(json);
      expect(restored.useLatest, isTrue);
      expect(restored.referenceTime, ReleaseEvidenceTestFixtures.referenceTime);
    });

    test('ReleaseEvidenceResult roundtrip', () {
      roundTrip<ReleaseEvidenceResult>(
        original: ReleaseEvidenceTestFixtures.validResult(),
        toJson: (r) => r.toJson(),
        fromJson: ReleaseEvidenceResult.fromJson,
        assertEqual: (r) =>
            expect(r.status, ReleaseEvidenceResultStatus.success),
      );
    });

    test('policies roundtrip via json', () {
      final evidence = ReleaseEvidencePolicyV1.create();
      final attestation = ReleaseAttestationPolicyV1.create();
      final verification = ReleaseVerificationPolicyV1.create();

      final evidenceRestored =
          ReleaseEvidencePolicy.fromJson(evidence.toJson());
      final attestationRestored =
          ReleaseAttestationPolicy.fromJson(attestation.toJson());
      final verificationRestored =
          ReleaseVerificationPolicy.fromJson(verification.toJson());

      expect(evidenceRestored.metadata.policyId, evidence.metadata.policyId);
      expect(
          attestationRestored.metadata.policyId, attestation.metadata.policyId);
      expect(
        verificationRestored.metadata.policyId,
        verification.metadata.policyId,
      );
    });

    test('enum wire names roundtrip', () {
      for (final status in ReleaseVerificationStatus.values) {
        expect(
          ReleaseVerificationStatusX.fromWireName(status.wireName),
          status,
        );
      }
      for (final status in ReleaseEvidencePolicyStatus.values) {
        expect(
          ReleaseEvidencePolicyStatusX.fromWireName(status.wireName),
          status,
        );
      }
    });

    test('referenceTime uses UTC Z suffix in fixtures', () {
      expect(ReleaseEvidenceTestFixtures.referenceTime.endsWith('Z'), isTrue);
    });

    test('unknown enum throws FormatException', () {
      expect(
        () => ReleaseVerificationStatusX.fromWireName('not-a-status'),
        throwsFormatException,
      );
    });
  });
}
