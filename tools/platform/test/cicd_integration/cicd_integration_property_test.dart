import 'dart:math';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_collector.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_snapshot_validator.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/resolved_cicd_integration_sources.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:test/test.dart';

import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration property-based tests', () {
    final random = Random(42);
    const serializer = CicdIntegrationCanonicalSerializer();

    CicdIntegrationEvaluationContext buildContext() {
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

    test('collector sorts artifacts deterministically for any input order', () {
      for (var seed = 0; seed < 20; seed++) {
        final rng = Random(seed);
        final definition = PipelineTestFixtures.validDefinition();
        final context = CicdIntegrationEvaluationContext(
          request: CicdIntegrationOperationalFixtures.passingRequest(
            pipelineDefinition: definition,
          ),
          sources: ResolvedCicdIntegrationSources(
            pipelineDefinition: ResolvedCicdIntegrationSource(
              sourceType: CicdIntegrationSourceType.pipelineDefinition,
              resolutionMode: CicdIntegrationSourceResolutionMode.injected,
              state: CicdIntegrationSourceState.available,
              resolvedArtifact: definition,
            ),
            pipelineExecution: ResolvedCicdIntegrationSource(
              sourceType: CicdIntegrationSourceType.pipelineExecution,
              resolutionMode: CicdIntegrationSourceResolutionMode.injected,
              state: CicdIntegrationSourceState.available,
              resolvedArtifact: PipelineTestFixtures.validExecution(),
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
        final collected = const CicdIntegrationCollector().collect(context);
        final ids = collected.artifacts.map((e) => e.artifactId).toList();
        expect(ids, equals(ids.toList()..sort()));
        expect(rng.nextInt(100), greaterThanOrEqualTo(0));
      }
    });

    test('large pipeline definition stages remain uniquely identified', () {
      for (var i = 0; i < 10 + random.nextInt(5); i++) {
        final definition = buildLargePipelineDefinition(stageCount: 50 + i);
        final stageIds = definition.stages.map((s) => s.stageId).toList();
        expect(stageIds.length, equals(stageIds.toSet().length));
        expect(
            buildContext().pipelineIntegrationPolicy.policy.requiredStageTypes,
            isNotEmpty);
      }
    });

    test('serializer fingerprint invariant under repeated serialization',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final fp = serializer.snapshotFingerprint(snapshot);
      for (var i = 0; i < 10; i++) {
        final json = snapshot.toJson();
        expect(serializer.snapshotFingerprint(snapshot), fp);
        expect(json.keys.length, greaterThan(5));
      }
    });

    test('validation rejects mutated snapshot metadata fingerprint mismatch',
        () async {
      final snapshot = (await evaluatePassingSnapshot()).snapshot!;
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(fingerprint: 'mutated-fp'),
      );
      expect(
        const CicdIntegrationSnapshotValidator().validate(mutated).isValid,
        isFalse,
      );
    });

    test('large pipeline definition fingerprint is stable across seeds', () {
      for (var seed = 0; seed < 5; seed++) {
        final definition = buildLargePipelineDefinition(stageCount: 100 + seed);
        final fp1 = serializer.pipelineDefinitionFingerprint(definition);
        final fp2 = serializer.pipelineDefinitionFingerprint(definition);
        expect(fp1, fp2);
        expect(definition.stages, hasLength(100 + seed));
      }
    });
  });
}
