import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_artifact_registry.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_exceptions.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_identity_builder.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_policy_registry.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/stores/in_memory_cicd_integration_store.dart';
import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_query.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  late CicdIntegrationProvider cicdProvider;

  setUp(() {
    cicdProvider =
        PlatformBootstrap.forRepo(Directory.current.path).cicdIntegration();
  });

  group('PipelineIntegrationPolicyRegistry', () {
    test('registers candidate policy and resolves without implicit latest', () {
      final registry = PipelineIntegrationPolicyRegistry();
      registry.register(PipelineIntegrationPolicyV1.create());
      registry.freeze();

      expect(
          registry.candidate(PipelineIntegrationPolicyV1.policyId), isNotNull);
      expect(registry.active(PipelineIntegrationPolicyV1.policyId), isNull);
      expect(
        registry.resolve(
          policyId: PipelineIntegrationPolicyV1.policyId,
          allowCandidate: true,
        ),
        isNotNull,
      );
      expect(
        registry.resolve(
          policyId: PipelineIntegrationPolicyV1.policyId,
          allowCandidate: false,
        ),
        isNull,
      );
    });

    test('getLatestVersion is opt-in and distinct from resolve', () {
      final registry = PipelineIntegrationPolicyRegistry();
      registry.register(PipelineIntegrationPolicyV1.create());
      registry.freeze();

      expect(registry.getLatestVersion(PipelineIntegrationPolicyV1.policyId),
          isNotNull);
      expect(registry.get(PipelineIntegrationPolicyV1.policyId, 1), isNotNull);
    });

    test('promote deprecate and retire transition lifecycle', () {
      final registry = PipelineIntegrationPolicyRegistry();
      registry.register(PipelineIntegrationPolicyV1.create());

      registry.promote(PipelineIntegrationPolicyV1.policyId, 1);
      expect(registry.active(PipelineIntegrationPolicyV1.policyId), isNotNull);
      expect(registry.candidate(PipelineIntegrationPolicyV1.policyId), isNull);

      registry.deprecate(PipelineIntegrationPolicyV1.policyId, 1);
      expect(
          registry.deprecated(PipelineIntegrationPolicyV1.policyId), isNotNull);
      expect(registry.active(PipelineIntegrationPolicyV1.policyId), isNull);

      registry.retire(PipelineIntegrationPolicyV1.policyId, 1);
      expect(registry.retired(PipelineIntegrationPolicyV1.policyId), isNotNull);
      expect(
        registry.resolve(policyId: PipelineIntegrationPolicyV1.policyId),
        isNull,
      );
    });

    test('frozen registry rejects registration and transitions', () {
      final registry = PipelineIntegrationPolicyRegistry();
      registry.register(PipelineIntegrationPolicyV1.create());
      registry.freeze();

      expect(
        () => registry.register(PipelineIntegrationPolicyV1.create()),
        throwsA(isA<CicdIntegrationRegistryFrozenException>()),
      );
      expect(
        () => registry.promote(PipelineIntegrationPolicyV1.policyId, 1),
        throwsA(isA<CicdIntegrationRegistryFrozenException>()),
      );
    });
  });

  group('PipelineExecutionPolicyRegistry', () {
    test('registers pipeline execution policy v1', () {
      final registry = PipelineExecutionPolicyRegistry();
      registry.register(PipelineExecutionPolicyV1.create());
      registry.freeze();

      expect(registry.contains(PipelineExecutionPolicyV1.policyId, 1), isTrue);
    });
  });

  group('DeploymentIntegrationPolicyRegistry', () {
    test('registers deployment integration policy v1', () {
      final registry = DeploymentIntegrationPolicyRegistry();
      registry.register(DeploymentIntegrationPolicyV1.create());
      registry.freeze();

      expect(
          registry.contains(DeploymentIntegrationPolicyV1.policyId, 1), isTrue);
    });
  });

  group('CicdIntegrationCanonicalSerializer', () {
    const serializer = CicdIntegrationCanonicalSerializer();

    test('snapshot fingerprint is deterministic across 5 iterations', () async {
      final request = CicdIntegrationOperationalFixtures.passingRequest();
      final fingerprints = <String>[];
      for (var i = 0; i < 5; i++) {
        final result = await cicdProvider.evaluate(request);
        fingerprints.add(result.snapshot!.fingerprint);
      }
      expect(fingerprints.toSet().length, 1);
      expect(fingerprints.first, isNotEmpty);
    });

    test('pipeline definition fingerprint is deterministic', () {
      final definition = PipelineTestFixtures.validDefinition();
      final first = serializer.pipelineDefinitionFingerprint(definition);
      final second = serializer.pipelineDefinitionFingerprint(definition);
      expect(first, second);
    });

    test('request fingerprint is deterministic', () {
      final request = CicdIntegrationOperationalFixtures.passingRequest();
      final first = serializer.requestFingerprint(request);
      final second = serializer.requestFingerprint(request);
      expect(first, second);
    });
  });

  group('CicdIntegrationIdentityBuilder', () {
    const identity = CicdIntegrationIdentityBuilder();

    test('builds stable cicd integration id from normative fields', () async {
      final snapshot = await _buildSnapshot(cicdProvider);
      final id = identity.buildCicdIntegrationIdFromSnapshot(snapshot);
      expect(id, contains(snapshot.metadata.projectId));
      expect(id, contains(snapshot.fingerprint));
    });

    test('component fingerprints are stable', () {
      final definition = PipelineTestFixtures.validDefinition();
      final execution = PipelineTestFixtures.validExecution();
      final plan = PipelineTestFixtures.validDeploymentPlan();
      expect(identity.pipelineFingerprint(definition),
          identity.pipelineFingerprint(definition));
      expect(identity.executionFingerprint(execution),
          identity.executionFingerprint(execution));
      expect(identity.deploymentPlanFingerprint(plan),
          identity.deploymentPlanFingerprint(plan));
    });
  });

  group('InMemoryCicdIntegrationStore', () {
    test('save is idempotent for same fingerprint', () async {
      final store = InMemoryCicdIntegrationStore();
      final snapshot = await _buildSnapshot(cicdProvider);

      await store.save(snapshot);
      await store.save(snapshot);

      final loaded =
          await store.load(snapshot.metadata.cicdIntegrationSnapshotId);
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, snapshot.fingerprint);
    });

    test('save throws conflict for same id with different normative content',
        () async {
      final store = InMemoryCicdIntegrationStore();
      final snapshot = await _buildSnapshot(cicdProvider);
      await store.save(snapshot);

      final conflicting = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          cicdIntegrationSnapshotId:
              snapshot.metadata.cicdIntegrationSnapshotId,
          pipelineIntegrationPolicyVersion: 99,
        ),
      );

      await expectLater(
        store.save(conflicting),
        throwsA(isA<CicdIntegrationSnapshotConflictException>()),
      );
    });

    test('query filters by projectId', () async {
      final store = InMemoryCicdIntegrationStore();
      final snapshot = await _buildSnapshot(cicdProvider);
      await store.save(snapshot);

      final results = await store.query(
        const CicdIntegrationQuery(
          projectId: CicdIntegrationOperationalFixtures.projectId,
        ),
      );
      expect(results, isNotEmpty);
    });
  });

  group('CicdIntegrationArtifactRegistry', () {
    test('loads registered pipeline and deployment artifacts', () {
      final registry = CicdIntegrationArtifactRegistry();
      final definition = PipelineTestFixtures.validDefinition();
      final execution = PipelineTestFixtures.validExecution();
      final plan = PipelineTestFixtures.validDeploymentPlan();

      registry.registerDefinition(definition);
      registry.registerExecution(execution);
      registry.registerDeploymentPlan(plan);

      expect(registry.loadDefinition('def-ci-001'), definition);
      expect(registry.loadExecution('exec-001'), execution);
      expect(registry.loadDeploymentPlan('plan-001'), plan);
    });

    test('latestDefinition returns highest version for project', () {
      final registry = CicdIntegrationArtifactRegistry();
      final v1 = PipelineTestFixtures.validDefinition();
      final v2 = v1.copyWith(version: 2, definitionId: 'def-ci-002');

      registry.registerDefinition(v1);
      registry.registerDefinition(v2);

      expect(
        registry.latestDefinition(projectId: PipelineTestFixtures.projectId),
        v2,
      );
    });
  });
}

Future<CicdIntegrationSnapshot> _buildSnapshot(
  CicdIntegrationProvider provider,
) async {
  final result = await provider.evaluate(
    CicdIntegrationOperationalFixtures.passingRequest(),
  );
  return result.snapshot!;
}
