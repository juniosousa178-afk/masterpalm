import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_exceptions.dart';
import 'package:masterpalm_platform/cryptographic_trust/cryptographic_trust_policy_registry.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_enums.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/cryptographic_trust_policy.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/artifact_signature_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/attestation_trust_policy_v1.dart';
import 'package:masterpalm_platform/models/cryptographic_trust/policies/release_trust_policy_v1.dart';
import 'package:test/test.dart';

import 'support/cryptographic_trust_test_fixtures.dart';

void main() {
  group('CryptographicTrustPolicyRegistry', () {
    late CryptographicTrustPolicyRegistry registry;

    setUp(() {
      registry = CryptographicTrustPolicyRegistry();
    });

    test('register stores valid policy', () {
      final policy = CryptographicTrustTestFixtures.validPolicy();
      registry.register(policy);
      expect(registry.contains(policy.policyId, policy.version), isTrue);
    });

    test('register rejects duplicate policy version', () {
      final policy = CryptographicTrustTestFixtures.validPolicy();
      registry.register(policy);
      expect(() => registry.register(policy),
          throwsA(isA<CryptographicTrustPolicyInvalidException>()));
    });

    test('registerDefaultPolicies registers three factory policies', () {
      registry.registerDefaultPolicies();
      expect(
        registry.contains(ArtifactSignatureTrustPolicyV1.policyId, 1),
        isTrue,
      );
      expect(registry.contains(AttestationTrustPolicyV1.policyId, 1), isTrue);
      expect(registry.contains(ReleaseTrustPolicyV1.policyId, 1), isTrue);
    });

    test('resolveById returns exact version', () {
      registry.registerDefaultPolicies();
      final policy = registry.resolveById(
        ArtifactSignatureTrustPolicyV1.policyId,
        1,
      );
      expect(policy, isNotNull);
      expect(policy!.policyId, ArtifactSignatureTrustPolicyV1.policyId);
    });

    test('resolve without version returns active policy', () {
      final active = ArtifactSignatureTrustPolicyV1.create().copyWith(
        status: CryptographicPolicyStatus.active,
      );
      registry.register(active);
      final resolved = registry.resolve(
        policyId: ArtifactSignatureTrustPolicyV1.policyId,
      );
      expect(resolved?.status, CryptographicPolicyStatus.active);
    });

    test('resolve does not return latest without useLatest opt-in', () {
      registry.register(
        ArtifactSignatureTrustPolicyV1.create().copyWith(
          version: 1,
          status: CryptographicPolicyStatus.deprecated,
        ),
      );
      registry.register(
        ArtifactSignatureTrustPolicyV1.create().copyWith(
          version: 2,
          status: CryptographicPolicyStatus.candidate,
        ),
      );
      final resolved = registry.resolve(
        policyId: ArtifactSignatureTrustPolicyV1.policyId,
      );
      expect(resolved, isNull);
    });

    test('resolve with useLatest returns highest version', () {
      registry.register(
        ArtifactSignatureTrustPolicyV1.create().copyWith(
          version: 1,
          status: CryptographicPolicyStatus.retired,
        ),
      );
      registry.register(
        ArtifactSignatureTrustPolicyV1.create().copyWith(
          version: 2,
          status: CryptographicPolicyStatus.candidate,
        ),
      );
      final resolved = registry.resolve(
        policyId: ArtifactSignatureTrustPolicyV1.policyId,
        useLatest: true,
      );
      expect(resolved?.version, 2);
    });

    test('resolve with allowCandidate returns candidate when no active', () {
      registry.register(ArtifactSignatureTrustPolicyV1.create());
      final resolved = registry.resolve(
        policyId: ArtifactSignatureTrustPolicyV1.policyId,
        allowCandidate: true,
      );
      expect(resolved?.status, CryptographicPolicyStatus.candidate);
    });

    test('candidate requires explicit selection semantics via status lookup',
        () {
      registry.register(ArtifactSignatureTrustPolicyV1.create());
      final candidate =
          registry.candidate(ArtifactSignatureTrustPolicyV1.policyId);
      expect(candidate?.status, CryptographicPolicyStatus.candidate);
    });

    test('promote transitions policy to active', () {
      registry.register(ArtifactSignatureTrustPolicyV1.create());
      registry.promote(ArtifactSignatureTrustPolicyV1.policyId, 1);
      expect(
        registry.active(ArtifactSignatureTrustPolicyV1.policyId)?.status,
        CryptographicPolicyStatus.active,
      );
    });

    test('deprecate transitions policy to deprecated', () {
      final active = ArtifactSignatureTrustPolicyV1.create().copyWith(
        status: CryptographicPolicyStatus.active,
      );
      registry.register(active);
      registry.deprecate(ArtifactSignatureTrustPolicyV1.policyId, 1);
      expect(
        registry.deprecated(ArtifactSignatureTrustPolicyV1.policyId)?.status,
        CryptographicPolicyStatus.deprecated,
      );
    });

    test('retire transitions policy to retired', () {
      final active = ArtifactSignatureTrustPolicyV1.create().copyWith(
        status: CryptographicPolicyStatus.active,
      );
      registry.register(active);
      registry.retire(ArtifactSignatureTrustPolicyV1.policyId, 1);
      expect(
        registry.retired(ArtifactSignatureTrustPolicyV1.policyId)?.status,
        CryptographicPolicyStatus.retired,
      );
    });

    test('resolve hides retired policy unless historicalEvaluation', () {
      final active = ArtifactSignatureTrustPolicyV1.create().copyWith(
        status: CryptographicPolicyStatus.active,
      );
      registry.register(active);
      registry.retire(ArtifactSignatureTrustPolicyV1.policyId, 1);
      expect(
        registry.resolve(
          policyId: ArtifactSignatureTrustPolicyV1.policyId,
          policyVersion: 1,
        ),
        isNull,
      );
      expect(
        registry.resolve(
          policyId: ArtifactSignatureTrustPolicyV1.policyId,
          policyVersion: 1,
          historicalEvaluation: true,
        ),
        isNotNull,
      );
    });

    test('freeze prevents further registration', () {
      registry.register(ArtifactSignatureTrustPolicyV1.create());
      registry.freeze();
      expect(
        () => registry.register(AttestationTrustPolicyV1.create()),
        throwsA(isA<CryptographicTrustRegistryFrozenException>()),
      );
    });

    test('list returns policies sorted by id then version', () {
      registry.register(
        ArtifactSignatureTrustPolicyV1.create().copyWith(version: 2),
      );
      registry.register(
        AttestationTrustPolicyV1.create().copyWith(version: 1),
      );
      final listed = registry.list();
      expect(listed.first.policyId, ArtifactSignatureTrustPolicyV1.policyId);
    });

    test('promote missing policy throws not found', () {
      expect(
        () => registry.promote('missing-policy', 1),
        throwsA(isA<CryptographicTrustPolicyNotFoundException>()),
      );
    });
  });
}
