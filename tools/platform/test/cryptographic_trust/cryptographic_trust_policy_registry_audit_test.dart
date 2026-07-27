import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_policy_registry.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/attestation_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/release_trust_policy_v1.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_operational_fixtures.dart';
import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('Cryptographic Trust policy registry audit', () {
    test('registerDefaultPolicies registers three factory policies', () {
      final registry = CryptographicTrustPolicyRegistry()
        ..registerDefaultPolicies();
      expect(registry.contains(ArtifactSignatureTrustPolicyV1.policyId, 1),
          isTrue);
      expect(registry.contains(AttestationTrustPolicyV1.policyId, 1), isTrue);
      expect(registry.contains(ReleaseTrustPolicyV1.policyId, 1), isTrue);
    });

    test('resolveById returns exact version', () {
      final registry =
          CryptographicTrustOperationalFixtures.createPolicyRegistry(
        registerDefaults: true,
        freeze: true,
      );
      final policy = registry.resolveById(
        ArtifactSignatureTrustPolicyV1.policyId,
        1,
      );
      expect(policy?.policyId, ArtifactSignatureTrustPolicyV1.policyId);
    });

    test('duplicate registration throws invalid exception', () {
      final registry = CryptographicTrustPolicyRegistry();
      final policy = CryptographicTrustTestFixtures.validPolicy();
      registry.register(policy);
      expect(
        () => registry.register(policy),
        throwsA(isA<CryptographicTrustPolicyInvalidException>()),
      );
    });

    test('frozen registry rejects registration', () {
      final registry = CryptographicTrustPolicyRegistry()
        ..registerDefaultPolicies()
        ..freeze();
      expect(
        () => registry.register(CryptographicTrustTestFixtures.validPolicy()),
        throwsA(isA<CryptographicTrustRegistryFrozenException>()),
      );
    });

    test('resolve missing policy returns null', () {
      final registry = CryptographicTrustPolicyRegistry();
      expect(registry.resolveById('missing-policy', 1), isNull);
    });

    test('candidate policy resolved when allowCandidate true', () {
      final registry = CryptographicTrustPolicyRegistry();
      final candidate = ArtifactSignatureTrustPolicyV1.create().copyWith(
        status: CryptographicPolicyStatus.candidate,
      );
      registry.register(candidate);
      final resolved = registry.resolve(
        policyId: ArtifactSignatureTrustPolicyV1.policyId,
        allowCandidate: true,
      );
      expect(resolved?.status, CryptographicPolicyStatus.candidate);
    });
  });
}
