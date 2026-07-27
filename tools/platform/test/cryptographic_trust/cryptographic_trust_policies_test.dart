import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/attestation_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/release_trust_policy_v1.dart';
import 'package:test/test.dart';

void main() {
  group('Cryptographic Trust policy v1 factories', () {
    test('ArtifactSignatureTrustPolicyV1.create returns expected policyId', () {
      final policy = ArtifactSignatureTrustPolicyV1.create();
      expect(policy.policyId, ArtifactSignatureTrustPolicyV1.policyId);
      expect(policy.policyId, 'artifact-signature-trust-v1');
    });

    test('AttestationTrustPolicyV1.create returns expected policyId', () {
      final policy = AttestationTrustPolicyV1.create();
      expect(policy.policyId, AttestationTrustPolicyV1.policyId);
      expect(policy.policyId, 'attestation-trust-v1');
    });

    test('ReleaseTrustPolicyV1.create returns expected policyId', () {
      final policy = ReleaseTrustPolicyV1.create();
      expect(policy.policyId, ReleaseTrustPolicyV1.policyId);
      expect(policy.policyId, 'release-trust-v1');
    });

    test('artifact signature policy includes signature and digest requirements',
        () {
      final policy = ArtifactSignatureTrustPolicyV1.create();
      expect(policy.requirements, hasLength(2));
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.signature),
      );
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.digest),
      );
    });

    test('attestation policy includes attestation and signature requirements',
        () {
      final policy = AttestationTrustPolicyV1.create();
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.attestation),
      );
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.signature),
      );
    });

    test('release trust policy includes release-oriented requirements', () {
      final policy = ReleaseTrustPolicyV1.create();
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.signature),
      );
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.attestation),
      );
      expect(
        policy.requirements.map((r) => r.requirementType),
        contains(CryptographicRequirementType.transparencyLog),
      );
    });

    test('all v1 policies are version 1 candidate policies', () {
      final policies = <CryptographicTrustPolicy>[
        ArtifactSignatureTrustPolicyV1.create(),
        AttestationTrustPolicyV1.create(),
        ReleaseTrustPolicyV1.create(),
      ];
      for (final policy in policies) {
        expect(policy.version, 1);
        expect(policy.status, CryptographicPolicyStatus.candidate);
        expect(policy.scope['domain'], 'cryptographic-trust');
      }
    });

    test('policy factories roundtrip via json', () {
      final policies = [
        ArtifactSignatureTrustPolicyV1.create(),
        AttestationTrustPolicyV1.create(),
        ReleaseTrustPolicyV1.create(),
      ];
      for (final policy in policies) {
        final restored = CryptographicTrustPolicy.fromJson(policy.toJson());
        expect(restored.policyId, policy.policyId);
        expect(restored.version, policy.version);
        expect(
          restored.toComparableJson(),
          equals(policy.toComparableJson()),
        );
      }
    });

    test('policy metadata documents structural limitations', () {
      final artifactPolicy = ArtifactSignatureTrustPolicyV1.create();
      final attestationPolicy = AttestationTrustPolicyV1.create();
      final releasePolicy = ReleaseTrustPolicyV1.create();
      expect(artifactPolicy.metadata['limitations'], isNotEmpty);
      expect(attestationPolicy.metadata['limitations'], isNotEmpty);
      expect(releasePolicy.metadata['limitations'],
          contains('no-release-authorization'));
    });
  });
}
