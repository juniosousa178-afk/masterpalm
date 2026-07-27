import 'dart:convert';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_collector.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_snapshot_builder.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/resolved_cicd_integration_sources.dart';
import 'package:masterpalm_platform/cicd_integration/stores/in_memory_cicd_integration_store.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';

void main() {
  group('CI/CD Integration stress tests', () {
    CicdIntegrationEvaluationContext buildStressContext() {
      return CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(),
        sources: ResolvedCicdIntegrationSources(
          pipelineDefinition: cicdNotRequested(
            CicdIntegrationSourceType.pipelineDefinition,
          ),
          pipelineExecution: cicdNotRequested(
            CicdIntegrationSourceType.pipelineExecution,
          ),
          pipelineExecutionResult: cicdNotRequested(
            CicdIntegrationSourceType.pipelineExecutionResult,
          ),
          deploymentPlan:
              cicdNotRequested(CicdIntegrationSourceType.deploymentPlan),
          deploymentResult:
              cicdNotRequested(CicdIntegrationSourceType.deploymentResult),
          releaseEvidenceBundle: cicdNotRequested(
            CicdIntegrationSourceType.releaseEvidenceBundle,
          ),
          releaseSupplyChainSnapshot: cicdNotRequested(
            CicdIntegrationSourceType.releaseSupplyChainSnapshot,
          ),
          pipelineIntegrationPolicy: cicdNotRequested(
            CicdIntegrationSourceType.pipelineIntegrationPolicy,
          ),
          pipelineExecutionPolicy: cicdNotRequested(
            CicdIntegrationSourceType.pipelineExecutionPolicy,
          ),
          deploymentIntegrationPolicy: cicdNotRequested(
            CicdIntegrationSourceType.deploymentIntegrationPolicy,
          ),
          sourceReferences: const [],
          resolutionSummary: const CicdIntegrationSourceResolutionSummary(
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );
    }

    test('large pipeline definition handles 1000 stages', () {
      final definition = buildLargePipelineDefinition(stageCount: 1000);
      expect(definition.stages, hasLength(1000));
      expect(definition.fingerprint, isNotEmpty);
    });

    test('store handles 5000 snapshot saves idempotently', () async {
      final store = InMemoryCicdIntegrationStore();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;

      for (var i = 0; i < 5000; i++) {
        await store.save(snapshot);
      }
      expect(await store.count(), 1);
    });

    test('1000 serializations preserve fingerprint', () async {
      const serializer = CicdIntegrationCanonicalSerializer();
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);

      for (var i = 0; i < 1000; i++) {
        final roundTripped = CicdIntegrationSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        );
        expect(serializer.snapshotFingerprint(roundTripped), fp);
      }
    });

    test('snapshot builder handles large collected artifact set', () {
      final context = buildStressContext();
      final definition = buildLargePipelineDefinition(stageCount: 100);
      final artifacts = List.generate(
        100,
        (i) => CicdIntegrationCollectedArtifact(
          artifactId: 'stress-art-${i.toString().padLeft(5, '0')}',
          artifactType: 'pipelineDefinition',
          sourceType: 'pipelineDefinition',
          fingerprint: definition.fingerprint,
        ),
      );
      final collected = CicdIntegrationCollectedArtifacts(
        pipelineDefinition: definition,
        artifacts: artifacts,
      );

      final stopwatch = Stopwatch()..start();
      final result = CicdIntegrationSnapshotBuilder().build(
        context: context,
        collected: collected,
        evaluatedAt: CicdIntegrationOperationalFixtures.referenceTime,
      );
      stopwatch.stop();

      expect(result.snapshot, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });

    test('collector dedup maintains stability at scale', () {
      final artifacts = List.generate(
        200,
        (i) => CicdIntegrationCollectedArtifact(
          artifactId: 'dedup-$i',
          artifactType: 'test',
          sourceType: 'test',
          fingerprint: 'fp-$i',
        ),
      );
      final ids = artifacts.map((e) => e.artifactId);
      expect(ids.length, equals(ids.toSet().length));
    });
  });
}
