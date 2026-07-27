import 'package:masterpalm_platform/cicd_integration/cicd_integration_collector.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_engine.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_snapshot_builder.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/resolved_cicd_integration_sources.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_messages.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_result.dart';
import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

CicdIntegrationEvaluationContext _buildContext({
  PipelineDefinition? definition,
  PipelineExecution? execution,
}) {
  final pipelineDefinition =
      definition ?? PipelineTestFixtures.validDefinition();
  final pipelineExecution = execution ?? PipelineTestFixtures.validExecution();

  return CicdIntegrationEvaluationContext(
    request: CicdIntegrationOperationalFixtures.passingRequest(
      pipelineDefinition: pipelineDefinition,
      pipelineExecution: pipelineExecution,
    ),
    sources: ResolvedCicdIntegrationSources(
      pipelineDefinition: ResolvedCicdIntegrationSource(
        sourceType: CicdIntegrationSourceType.pipelineDefinition,
        resolutionMode: CicdIntegrationSourceResolutionMode.injected,
        state: CicdIntegrationSourceState.available,
        resolvedArtifact: pipelineDefinition,
      ),
      pipelineExecution: ResolvedCicdIntegrationSource(
        sourceType: CicdIntegrationSourceType.pipelineExecution,
        resolutionMode: CicdIntegrationSourceResolutionMode.injected,
        state: CicdIntegrationSourceState.available,
        resolvedArtifact: pipelineExecution,
      ),
      pipelineExecutionResult: ResolvedCicdIntegrationSource(
        sourceType: CicdIntegrationSourceType.pipelineExecutionResult,
        resolutionMode: CicdIntegrationSourceResolutionMode.injected,
        state: CicdIntegrationSourceState.available,
        resolvedArtifact: PipelineTestFixtures.validExecutionResult(),
      ),
      deploymentPlan: ResolvedCicdIntegrationSource(
        sourceType: CicdIntegrationSourceType.deploymentPlan,
        resolutionMode: CicdIntegrationSourceResolutionMode.injected,
        state: CicdIntegrationSourceState.available,
        resolvedArtifact: PipelineTestFixtures.validDeploymentPlan(),
      ),
      deploymentResult: ResolvedCicdIntegrationSource(
        sourceType: CicdIntegrationSourceType.deploymentResult,
        resolutionMode: CicdIntegrationSourceResolutionMode.injected,
        state: CicdIntegrationSourceState.available,
        resolvedArtifact: PipelineTestFixtures.validDeploymentResult(),
      ),
      releaseEvidenceBundle: ResolvedCicdIntegrationSource(
        sourceType: CicdIntegrationSourceType.releaseEvidenceBundle,
        resolutionMode: CicdIntegrationSourceResolutionMode.injected,
        state: CicdIntegrationSourceState.available,
        resolvedArtifact: ReleaseEvidenceTestFixtures.validBundle(),
      ),
      releaseSupplyChainSnapshot: cicdNotRequested(
        CicdIntegrationSourceType.releaseSupplyChainSnapshot,
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
    ),
    pipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
    pipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
    deploymentIntegrationPolicy: DeploymentIntegrationPolicyV1.create(),
  );
}

void main() {
  group('CI/CD Integration engine audit', () {
    const engine = CicdIntegrationEngine();
    const collector = CicdIntegrationCollector();
    final snapshotBuilder = CicdIntegrationSnapshotBuilder();

    test('engine produces no errors for valid structural inputs', () {
      final context = _buildContext();
      final collected = collector.collect(context);
      final messages = engine.evaluate(
        context: context,
        collected: collected,
        pipelineDefinition: collected.pipelineDefinition,
        pipelineExecution: collected.pipelineExecution,
        pipelineExecutionResult: collected.pipelineExecutionResult,
        deploymentPlan: collected.deploymentPlan,
        deploymentResult: collected.deploymentResult,
      );

      expect(
        messages.where(
          (m) => m.severity == CicdIntegrationMessageSeverity.error,
        ),
        isEmpty,
      );
    });

    test('engine flags missing definition structurally', () {
      final context = _buildContext();
      final collected = collector.collect(context);
      final messages = engine.evaluate(
        context: context,
        collected: collected,
        pipelineDefinition: null,
        pipelineExecution: collected.pipelineExecution,
      );

      expect(
        messages.any((m) => m.code == 'CICD_STRUCT_MISSING_DEFINITION'),
        isTrue,
      );
    });

    test('engine flags execution-definition mismatch', () {
      final definition = PipelineTestFixtures.validDefinition();
      final wrongExecution =
          CicdIntegrationOperationalFixtures.wrongDefinitionExecution();
      final context = _buildContext(
        definition: definition,
        execution: wrongExecution,
      );
      final collected = collector.collect(context);
      final messages = engine.evaluate(
        context: context,
        collected: collected,
        pipelineDefinition: definition,
        pipelineExecution: wrongExecution,
      );

      expect(
        messages.any((m) => m.code == 'CICD_STRUCT_EXECUTION_DEFINITION'),
        isTrue,
      );
    });

    test('engine flags disallowed deployment strategy', () {
      final context = _buildContext();
      final collected = collector.collect(context);
      final badPlan = PipelineTestFixtures.validDeploymentPlan().copyWith(
        strategy: DeploymentStrategy.recreate,
      );
      final messages = engine.evaluate(
        context: context,
        collected: collected,
        pipelineDefinition: collected.pipelineDefinition,
        pipelineExecution: collected.pipelineExecution,
        deploymentPlan: badPlan,
      );

      expect(
        messages.any((m) => m.code == 'CICD_STRUCT_DISALLOWED_STRATEGY'),
        isTrue,
      );
    });

    test('builders do not mutate source artifact fingerprints', () {
      final definition = PipelineTestFixtures.validDefinition();
      final execution = PipelineTestFixtures.validExecution();
      final originalDefFp = definition.fingerprint;
      final originalExecFp = execution.fingerprint;
      final originalEvidenceFp =
          ReleaseEvidenceTestFixtures.validBundle().fingerprint;

      final context =
          _buildContext(definition: definition, execution: execution);
      final collected = collector.collect(context);

      engine.evaluate(
        context: context,
        collected: collected,
        pipelineDefinition: collected.pipelineDefinition,
        pipelineExecution: collected.pipelineExecution,
        pipelineExecutionResult: collected.pipelineExecutionResult,
        deploymentPlan: collected.deploymentPlan,
        deploymentResult: collected.deploymentResult,
      );
      snapshotBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: CicdIntegrationOperationalFixtures.referenceTime,
      );

      expect(collected.pipelineDefinition!.fingerprint, originalDefFp);
      expect(collected.pipelineExecution!.fingerprint, originalExecFp);
      expect(
        collected.releaseEvidenceBundle!.fingerprint,
        originalEvidenceFp,
      );
    });

    test('snapshot builder assembles components without mutating sources', () {
      final definition = PipelineTestFixtures.validDefinition();
      final definitionJsonBefore = definition.toJson();
      final context = _buildContext(definition: definition);
      final collected = collector.collect(context);

      final result = snapshotBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: CicdIntegrationOperationalFixtures.referenceTime,
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.pipelineDefinition, isNotNull);
      expect(result.snapshot!.pipelineExecution, isNotNull);
      expect(result.snapshot!.deploymentPlan, isNotNull);
      expect(definition.toJson(), equals(definitionJsonBefore));
    });

    test('engine evaluates structural rules only without side effects', () {
      final context = _buildContext();
      final collected = collector.collect(context);
      final messages = engine.evaluate(
        context: context,
        collected: collected,
        pipelineDefinition: collected.pipelineDefinition,
        pipelineExecution: collected.pipelineExecution,
        pipelineExecutionResult: collected.pipelineExecutionResult,
        deploymentPlan: collected.deploymentPlan,
        deploymentResult: collected.deploymentResult,
      );

      expect(messages, isNotEmpty);
      expect(
        messages.every((m) => m.operation == CicdIntegrationOperation.validate),
        isTrue,
      );
    });
  });
}
