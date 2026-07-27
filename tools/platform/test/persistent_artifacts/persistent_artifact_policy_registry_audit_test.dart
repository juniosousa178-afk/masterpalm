import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_test_fixtures.dart';

void main() {
  group('Persistent Artifact policy registry audit', () {
    test('registerDefaultPolicies provisions all base policy families', () {
      final registry = PersistentArtifactPolicyRegistry(registerDefaults: true);
      expect(registry.list().length, 4);
    });

    test('frozen registry rejects late registration', () {
      final registry = PersistentArtifactPolicyRegistry()..freeze();
      expect(
        () => registry.registerStorage(
          PersistentArtifactTestFixtures.validStoragePolicy(),
        ),
        throwsA(isA<PersistentArtifactRegistryFrozenException>()),
      );
    });

    test('resolveStorage returns active default policy', () {
      final registry = PersistentArtifactPolicyRegistry(registerDefaults: true);
      final storagePolicies =
          registry.list().whereType<PersistentArtifactStoragePolicy>().toList();
      expect(storagePolicies, isNotEmpty);
      final policy = registry.resolveStorage(
        policyId: storagePolicies.first.policyId,
        useLatest: true,
      );
      expect(policy, isNotNull);
      expect(policy!.policyId, storagePolicies.first.policyId);
    });
  });
}
