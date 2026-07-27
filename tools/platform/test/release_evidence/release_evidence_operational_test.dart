import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_query.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_attestation_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_verification_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_canonical_serializer.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_exceptions.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_identity_builder.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_policy_registry.dart';
import 'package:masterpalm_platform/release_evidence/stores/in_memory_release_evidence_store.dart';
import 'package:test/test.dart';

import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('ReleaseEvidencePolicyRegistry', () {
    test('registers candidate policy and resolves without implicit latest', () {
      final registry = ReleaseEvidencePolicyRegistry();
      registry.register(ReleaseEvidencePolicyV1.create());
      registry.freeze();

      expect(registry.candidate(ReleaseEvidencePolicyV1.policyId), isNotNull);
      expect(registry.active(ReleaseEvidencePolicyV1.policyId), isNull);
      expect(
        registry.resolve(
          policyId: ReleaseEvidencePolicyV1.policyId,
          allowCandidate: true,
        ),
        isNotNull,
      );
      expect(
        registry.resolve(
          policyId: ReleaseEvidencePolicyV1.policyId,
          allowCandidate: false,
        ),
        isNull,
      );
    });

    test('getLatestVersion is opt-in and distinct from resolve', () {
      final registry = ReleaseEvidencePolicyRegistry();
      registry.register(ReleaseEvidencePolicyV1.create());
      registry.freeze();

      expect(
        registry.getLatestVersion(ReleaseEvidencePolicyV1.policyId),
        isNotNull,
      );
      expect(registry.get(ReleaseEvidencePolicyV1.policyId, 1), isNotNull);
    });

    test('frozen registry rejects registration', () {
      final registry = ReleaseEvidencePolicyRegistry();
      registry.register(ReleaseEvidencePolicyV1.create());
      registry.freeze();

      expect(
        () => registry.register(ReleaseEvidencePolicyV1.create()),
        throwsA(isA<ReleaseEvidenceRegistryFrozenException>()),
      );
    });
  });

  group('ReleaseAttestationPolicyRegistry', () {
    test('registers attestation policy v1', () {
      final registry = ReleaseAttestationPolicyRegistry();
      registry.register(ReleaseAttestationPolicyV1.create());
      registry.freeze();

      expect(registry.contains(ReleaseAttestationPolicyV1.policyId, 1), isTrue);
    });
  });

  group('ReleaseVerificationPolicyRegistry', () {
    test('registers verification policy v1', () {
      final registry = ReleaseVerificationPolicyRegistry();
      registry.register(ReleaseVerificationPolicyV1.create());
      registry.freeze();

      expect(
          registry.contains(ReleaseVerificationPolicyV1.policyId, 1), isTrue);
    });
  });

  group('ReleaseEvidenceCanonicalSerializer', () {
    const serializer = ReleaseEvidenceCanonicalSerializer();

    test('bundle fingerprint is deterministic', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final first = serializer.bundleFingerprint(bundle);
      final second = serializer.bundleFingerprint(bundle);
      expect(first, second);
      expect(first, isNotEmpty);
    });

    test('verification fingerprint is deterministic', () {
      final result = ReleaseEvidenceTestFixtures.validVerificationResult();
      final first = serializer.verificationFingerprint(result);
      final second = serializer.verificationFingerprint(result);
      expect(first, second);
    });
  });

  group('ReleaseEvidenceIdentityBuilder', () {
    const identity = ReleaseEvidenceIdentityBuilder();

    test('builds stable bundle id from normative fields', () {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final id = identity.buildBundleIdFromBundle(bundle);
      expect(id, contains(bundle.metadata.projectId));
      expect(id, contains(bundle.metadata.releaseId));
      expect(id, contains(bundle.fingerprint));
    });

    test('builds stable verification id', () {
      final result = ReleaseEvidenceTestFixtures.validVerificationResult();
      final id = identity.buildVerificationIdFromResult(result);
      expect(id, startsWith('release-verification:'));
      expect(id, contains(result.fingerprint));
    });
  });

  group('InMemoryReleaseEvidenceStore', () {
    late InMemoryReleaseEvidenceStore store;

    setUp(() {
      store = InMemoryReleaseEvidenceStore();
    });

    test('save and load are idempotent', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);
      await store.save(bundle);

      final loaded = await store.load(bundle.metadata.bundleId);
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, bundle.fingerprint);
    });

    test('conflicting fingerprint throws', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);

      final conflicting = bundle.copyWith(
        metadata: bundle.metadata.copyWith(evidenceCount: 999),
      );
      await expectLater(
        store.save(conflicting),
        throwsA(isA<ReleaseEvidenceBundleConflictException>()),
      );
    });

    test('latest returns most recent bundle for project', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);

      final latest = await store.latest(projectId: bundle.metadata.projectId);
      expect(latest?.metadata.bundleId, bundle.metadata.bundleId);
    });

    test('query filters by project and release', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);

      final results = await store.query(
        ReleaseEvidenceQuery(
          projectId: bundle.metadata.projectId,
          releaseId: bundle.metadata.releaseId,
        ),
      );
      expect(results, hasLength(1));
    });

    test('invalidate removes bundle', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      await store.save(bundle);
      await store.invalidate(bundle.metadata.bundleId);
      expect(await store.load(bundle.metadata.bundleId), isNull);
    });
  });
}
