import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/policies/artifact_integrity_policy_v1.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/policies/artifact_replication_policy_v1.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/policies/artifact_retention_policy_v1.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/policies/artifact_storage_policy_v1.dart';
import 'package:test/test.dart';

void main() {
  group('PersistentArtifactPolicyRegistry', () {
    test('registra defaults', () {
      final registry = PersistentArtifactPolicyRegistry();
      registry.registerDefaultPolicies();
      expect(registry.list().length, 4);
    });

    test('freeze bloqueia registro', () {
      final registry = PersistentArtifactPolicyRegistry();
      registry.freeze();
      expect(
        () => registry.registerDefaultPolicies(),
        throwsA(isA<PersistentArtifactRegistryFrozenException>()),
      );
    });

    test('resolve storage candidato quando permitido', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      final policy = registry.resolveStorage(
        policyId: ArtifactStoragePolicyV1.policyId,
        allowCandidate: true,
      );
      expect(policy, isNotNull);
    });

    test('resolve storage sem candidato retorna nulo', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      final policy = registry.resolveStorage(
        policyId: ArtifactStoragePolicyV1.policyId,
      );
      expect(policy, isNull);
    });

    test('resolve retention por versao', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      final policy = registry.resolveRetention(
        policyId: ArtifactRetentionPolicyV1.policyId,
        policyVersion: 1,
      );
      expect(policy?.version, 1);
    });

    test('resolve integrity latest', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      final policy = registry.resolveIntegrity(
        policyId: ArtifactIntegrityPolicyV1.policyId,
        useLatest: true,
      );
      expect(policy, isNotNull);
    });

    test('resolve replication latest', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      final policy = registry.resolveReplication(
        policyId: ArtifactReplicationPolicyV1.policyId,
        useLatest: true,
      );
      expect(policy, isNotNull);
    });

    test('list combinado contem 4 itens', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      expect(registry.list().length, 4);
    });

    test('resolve inexistente retorna nulo', () {
      final registry = PersistentArtifactPolicyRegistry()
        ..registerDefaultPolicies();
      expect(
        registry.resolveIntegrity(policyId: 'inexistente', useLatest: true),
        isNull,
      );
    });

    test('registro manual storage funciona', () {
      final registry = PersistentArtifactPolicyRegistry();
      registry.registerStorage(ArtifactStoragePolicyV1.create());
      expect(registry.list().length, 1);
    });
  });
}
