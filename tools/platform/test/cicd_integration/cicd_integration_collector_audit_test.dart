import 'package:masterpalm_platform/cicd_integration/cicd_integration_collector.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/resolved_cicd_integration_sources.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration collector audit', () {
    const collector = CicdIntegrationCollector();

    ResolvedCicdIntegrationSources buildSources({
      required dynamic definition,
      required dynamic execution,
      required dynamic evidence,
      required dynamic supplyChain,
    }) {
      return ResolvedCicdIntegrationSources(
        pipelineDefinition: definition == null
            ? cicdNotRequested(CicdIntegrationSourceType.pipelineDefinition)
            : ResolvedCicdIntegrationSource(
                sourceType: CicdIntegrationSourceType.pipelineDefinition,
                resolutionMode: CicdIntegrationSourceResolutionMode.injected,
                state: CicdIntegrationSourceState.available,
                resolvedArtifact: definition,
                resolvedId: definition.definitionId,
                fingerprint: definition.fingerprint,
              ),
        pipelineExecution: execution == null
            ? cicdNotRequested(CicdIntegrationSourceType.pipelineExecution)
            : ResolvedCicdIntegrationSource(
                sourceType: CicdIntegrationSourceType.pipelineExecution,
                resolutionMode: CicdIntegrationSourceResolutionMode.injected,
                state: CicdIntegrationSourceState.available,
                resolvedArtifact: execution,
                resolvedId: execution.executionId,
                fingerprint: execution.fingerprint,
              ),
        pipelineExecutionResult: cicdNotRequested(
          CicdIntegrationSourceType.pipelineExecutionResult,
        ),
        deploymentPlan:
            cicdNotRequested(CicdIntegrationSourceType.deploymentPlan),
        deploymentResult:
            cicdNotRequested(CicdIntegrationSourceType.deploymentResult),
        releaseEvidenceBundle: evidence == null
            ? cicdNotRequested(CicdIntegrationSourceType.releaseEvidenceBundle)
            : ResolvedCicdIntegrationSource(
                sourceType: CicdIntegrationSourceType.releaseEvidenceBundle,
                resolutionMode: CicdIntegrationSourceResolutionMode.injected,
                state: CicdIntegrationSourceState.available,
                resolvedArtifact: evidence,
                resolvedId: evidence.metadata.bundleId,
                fingerprint: evidence.fingerprint,
              ),
        releaseSupplyChainSnapshot: supplyChain == null
            ? cicdNotRequested(
                CicdIntegrationSourceType.releaseSupplyChainSnapshot)
            : ResolvedCicdIntegrationSource(
                sourceType:
                    CicdIntegrationSourceType.releaseSupplyChainSnapshot,
                resolutionMode: CicdIntegrationSourceResolutionMode.injected,
                state: CicdIntegrationSourceState.available,
                resolvedArtifact: supplyChain,
                resolvedId: supplyChain.metadata.supplyChainSnapshotId,
                fingerprint: supplyChain.fingerprint,
              ),
        pipelineIntegrationPolicy: ResolvedCicdIntegrationSource(
          sourceType: CicdIntegrationSourceType.pipelineIntegrationPolicy,
          resolutionMode: CicdIntegrationSourceResolutionMode.injected,
          state: CicdIntegrationSourceState.available,
          resolvedArtifact: PipelineIntegrationPolicyV1.create(),
        ),
        pipelineExecutionPolicy: ResolvedCicdIntegrationSource(
          sourceType: CicdIntegrationSourceType.pipelineExecutionPolicy,
          resolutionMode: CicdIntegrationSourceResolutionMode.injected,
          state: CicdIntegrationSourceState.available,
          resolvedArtifact: PipelineExecutionPolicyV1.create(),
        ),
        deploymentIntegrationPolicy: ResolvedCicdIntegrationSource(
          sourceType: CicdIntegrationSourceType.deploymentIntegrationPolicy,
          resolutionMode: CicdIntegrationSourceResolutionMode.injected,
          state: CicdIntegrationSourceState.available,
          resolvedArtifact: DeploymentIntegrationPolicyV1.create(),
        ),
        sourceReferences: const [],
        resolutionSummary: const CicdIntegrationSourceResolutionSummary(
          resolvedSources: [],
          unresolvedSources: [],
          injectedSources: [],
        ),
      );
    }

    test('deduplicates artifacts by artifactId', () {
      final definition = PipelineTestFixtures.validDefinition();
      final execution = PipelineTestFixtures.validExecution();
      final evidence = ReleaseEvidenceTestFixtures.validBundle();
      final supplyChain =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();

      final context = CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        ),
        sources: buildSources(
          definition: definition,
          execution: execution,
          evidence: evidence,
          supplyChain: supplyChain,
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );
      final collected = collector.collect(context);
      final ids = collected.artifacts.map((e) => e.artifactId).toList();
      expect(ids, equals(ids.toSet().toList()..sort()));
    });

    test('does not duplicate definition fingerprint in multiple step artifacts',
        () {
      final definition = PipelineTestFixtures.validDefinition();
      final context = CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(),
        sources: buildSources(
          definition: definition,
          execution: null,
          evidence: null,
          supplyChain: null,
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );
      final collected = collector.collect(context);
      final definitionArtifacts = collected.artifacts
          .where((e) => e.artifactId == definition.definitionId)
          .toList();
      expect(definitionArtifacts, hasLength(1));
    });

    test('absent sources produce no artifacts for that type', () {
      final context = CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(),
        sources: buildSources(
          definition: null,
          execution: null,
          evidence: null,
          supplyChain: null,
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );
      final collected = collector.collect(context);
      expect(collected.pipelineDefinition, isNull);
      expect(collected.pipelineExecution, isNull);
      expect(collected.releaseEvidenceBundle, isNull);
      expect(collected.releaseSupplyChainSnapshot, isNull);
      expect(collected.artifacts, isEmpty);
    });

    test('artifacts reference fingerprints not payloads', () {
      final definition = PipelineTestFixtures.validDefinition();
      final context = CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(),
        sources: buildSources(
          definition: definition,
          execution: null,
          evidence: null,
          supplyChain: null,
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );
      final collected = collector.collect(context);
      for (final artifact in collected.artifacts) {
        expect(artifact.fingerprint, isNotEmpty);
        expect(artifact.fingerprint, definition.fingerprint);
      }
    });

    test('collector does not recalculate source fingerprints', () {
      final definition = PipelineTestFixtures.validDefinition();
      final evidence = ReleaseEvidenceTestFixtures.validBundle();
      final originalDefFp = definition.fingerprint;
      final originalEvidenceFp = evidence.fingerprint;
      final context = CicdIntegrationEvaluationContext(
        request: CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
        ),
        sources: buildSources(
          definition: definition,
          execution: PipelineTestFixtures.validExecution(),
          evidence: evidence,
          supplyChain: null,
        ),
        pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
      );
      final collected = collector.collect(context);
      expect(collected.pipelineDefinition!.fingerprint, originalDefFp);
      expect(collected.releaseEvidenceBundle!.fingerprint, originalEvidenceFp);
    });
  });
}
