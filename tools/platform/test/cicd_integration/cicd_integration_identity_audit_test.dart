import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_identity_builder.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration identity audit', () {
    const serializer = CicdIntegrationCanonicalSerializer();
    const identity = CicdIntegrationIdentityBuilder();

    Future<CicdIntegrationSnapshot> passingSnapshot() async {
      final result = await evaluatePassingSnapshot();
      return result.snapshot!;
    }

    test('snapshot fingerprint excludes snapshotId and temporal metadata',
        () async {
      final snapshot = await passingSnapshot();
      final fp1 = serializer.snapshotFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          cicdIntegrationSnapshotId: 'different-id',
          createdAt: '2099-01-01T00:00:00.000Z',
          evaluatedAt: '2099-01-01T00:00:00.000Z',
        ),
      );
      expect(serializer.snapshotFingerprint(mutated), fp1);
    });

    test('snapshot fingerprint changes when normative policy changes',
        () async {
      final snapshot = await passingSnapshot();
      final fp1 = serializer.snapshotFingerprint(snapshot);
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(
          pipelineIntegrationPolicyVersion: 99,
        ),
      );
      expect(serializer.snapshotFingerprint(mutated), isNot(fp1));
    });

    test('cicdIntegrationSnapshotId includes normative fingerprint components',
        () async {
      final snapshot = await passingSnapshot();
      final id = identity.buildCicdIntegrationIdFromSnapshot(snapshot);
      expect(id, contains(snapshot.metadata.projectId));
      expect(id, contains(snapshot.metadata.pipelineIntegrationPolicyId));
      expect(id, contains(snapshot.fingerprint));
    });

    test('pipeline definition fingerprint is stable for same normative content',
        () {
      final definition = PipelineTestFixtures.validDefinition();
      final fp1 = serializer.pipelineDefinitionFingerprint(definition);
      final fp2 = serializer.pipelineDefinitionFingerprint(definition);
      expect(fp1, fp2);
      expect(fp1, isNotEmpty);
    });

    test(
        'pipeline execution fingerprint excludes temporal startedAt/completedAt',
        () {
      final execution = PipelineTestFixtures.validExecution();
      final fp1 = serializer.pipelineExecutionFingerprint(execution);
      final mutated = execution.copyWith(
        startedAt: '2099-01-01T00:00:00.000Z',
        completedAt: '2099-01-01T00:00:00.000Z',
      );
      expect(serializer.pipelineExecutionFingerprint(mutated), fp1);
    });

    test(
        'pipeline execution fingerprint changes when normative definitionId changes',
        () {
      final execution = PipelineTestFixtures.validExecution();
      final fp1 = serializer.pipelineExecutionFingerprint(execution);
      final mutated = execution.copyWith(definitionId: 'different-definition');
      expect(serializer.pipelineExecutionFingerprint(mutated), isNot(fp1));
    });

    test('deployment plan fingerprint changes when normative strategy changes',
        () {
      final plan = PipelineTestFixtures.validDeploymentPlan();
      final fp1 = serializer.deploymentPlanFingerprint(plan);
      final mutated = plan.copyWith(strategy: DeploymentStrategy.recreate);
      expect(serializer.deploymentPlanFingerprint(mutated), isNot(fp1));
    });

    test('identity builder fingerprintForSnapshot matches serializer',
        () async {
      final snapshot = await passingSnapshot();
      expect(
        identity.fingerprintForSnapshot(snapshot),
        serializer.snapshotFingerprint(snapshot),
      );
    });

    test('component fingerprints match identity builder helpers', () async {
      final snapshot = await passingSnapshot();
      expect(
        identity.pipelineFingerprint(snapshot.pipelineDefinition),
        serializer.pipelineDefinitionFingerprint(snapshot.pipelineDefinition!),
      );
      expect(
        identity.executionFingerprint(snapshot.pipelineExecution),
        serializer.pipelineExecutionFingerprint(snapshot.pipelineExecution!),
      );
      expect(
        identity.deploymentPlanFingerprint(snapshot.deploymentPlan),
        serializer.deploymentPlanFingerprint(snapshot.deploymentPlan!),
      );
    });

    test('transient metadata mutation matrix does not change fingerprint',
        () async {
      final snapshot = await passingSnapshot();
      final baseline = serializer.snapshotFingerprint(snapshot);
      final transientMutations = [
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            cicdIntegrationSnapshotId: 'transient-id-1',
          ),
        ),
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            createdAt: '2000-01-01T00:00:00.000Z',
            evaluatedAt: '2000-01-01T00:00:00.000Z',
          ),
        ),
      ];
      for (final mutated in transientMutations) {
        expect(serializer.snapshotFingerprint(mutated), baseline);
      }
    });

    test('normative metadata mutation matrix changes fingerprint', () async {
      final snapshot = await passingSnapshot();
      final baseline = serializer.snapshotFingerprint(snapshot);
      final normativeMutations = [
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            pipelineExecutionPolicyVersion: 99,
          ),
        ),
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            deploymentIntegrationPolicyVersion: 99,
          ),
        ),
        snapshot.copyWith(
          metadata: snapshot.metadata.copyWith(
            status: CicdIntegrationSnapshotStatus.invalid,
          ),
        ),
      ];
      for (final mutated in normativeMutations) {
        expect(serializer.snapshotFingerprint(mutated), isNot(baseline));
      }
    });
  });
}
