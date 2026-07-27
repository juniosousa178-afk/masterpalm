import 'package:masterpalm_platform/cicd_integration/cicd_integration_artifact_registry.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_policy_registry.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_source_resolver.dart';
import 'package:masterpalm_platform/cicd_integration/policies/deployment_integration_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_execution_policy_v1.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cicd_integration_fake_providers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration source resolver audit', () {
    late FakeReleaseEvidenceProviderForCicd reProvider;
    late FakeReleaseSupplyChainProviderForCicd rscProvider;
    late CicdIntegrationSourceResolver resolver;

    setUp(() {
      reProvider = FakeReleaseEvidenceProviderForCicd();
      rscProvider = FakeReleaseSupplyChainProviderForCicd();
      resolver = CicdIntegrationSourceResolver(
        releaseEvidenceProvider: reProvider,
        releaseSupplyChainProvider: rscProvider,
        pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
          ..register(PipelineIntegrationPolicyV1.create())
          ..freeze(),
        pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
          ..register(PipelineExecutionPolicyV1.create())
          ..freeze(),
        deploymentIntegrationPolicyRegistry:
            DeploymentIntegrationPolicyRegistry()
              ..register(DeploymentIntegrationPolicyV1.create())
              ..freeze(),
      );
    });

    test('injected pipeline definition wins over byId and latest', () async {
      final registry = CicdIntegrationArtifactRegistry();
      final stored = PipelineTestFixtures.validDefinition().copyWith(
        definitionId: 'def-store-only',
      );
      registry.registerDefinition(stored);

      final injected = PipelineTestFixtures.validDefinition();
      final resolverWithRegistry = CicdIntegrationSourceResolver(
        releaseEvidenceProvider: reProvider,
        releaseSupplyChainProvider: rscProvider,
        artifactRegistry: registry,
        pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
          ..register(PipelineIntegrationPolicyV1.create())
          ..freeze(),
        pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
          ..register(PipelineExecutionPolicyV1.create())
          ..freeze(),
        deploymentIntegrationPolicyRegistry:
            DeploymentIntegrationPolicyRegistry()
              ..register(DeploymentIntegrationPolicyV1.create())
              ..freeze(),
      );

      final request = CicdIntegrationRequest(
        requestId: 'resolver-injected-def',
        projectId: CicdIntegrationOperationalFixtures.projectId,
        requestedAt: CicdIntegrationOperationalFixtures.referenceTime,
        pipelineDefinition: injected,
        pipelineDefinitionId: 'def-store-only',
        useLatest: true,
        pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
        pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
        deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
      );

      final sources = await resolverWithRegistry.resolveAll(
        request,
        injectedPipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        injectedPipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        injectedDeploymentIntegrationPolicy:
            DeploymentIntegrationPolicyV1.create(),
      );

      expect(
        sources.pipelineDefinition.resolutionMode,
        CicdIntegrationSourceResolutionMode.injected,
      );
      expect(
        sources.pipelineDefinition.resolvedArtifact!.definitionId,
        injected.definitionId,
      );
      expect(sources.resolutionSummary.injectedSources,
          contains('pipelineDefinition'));
    });

    test('byId resolves when injected absent', () async {
      final registry = CicdIntegrationArtifactRegistry();
      final stored = PipelineTestFixtures.validDefinition();
      registry.registerDefinition(stored);

      final resolverWithRegistry = CicdIntegrationSourceResolver(
        releaseEvidenceProvider: reProvider,
        releaseSupplyChainProvider: rscProvider,
        artifactRegistry: registry,
        pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
          ..register(PipelineIntegrationPolicyV1.create())
          ..freeze(),
        pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
          ..register(PipelineExecutionPolicyV1.create())
          ..freeze(),
        deploymentIntegrationPolicyRegistry:
            DeploymentIntegrationPolicyRegistry()
              ..register(DeploymentIntegrationPolicyV1.create())
              ..freeze(),
      );

      final request = CicdIntegrationRequest(
        requestId: 'resolver-by-id',
        projectId: CicdIntegrationOperationalFixtures.projectId,
        requestedAt: CicdIntegrationOperationalFixtures.referenceTime,
        pipelineDefinitionId: stored.definitionId,
        pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
        pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
        deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
      );

      final sources = await resolverWithRegistry.resolveAll(request);
      expect(sources.pipelineDefinition.isAvailable, isTrue);
      expect(
        sources.pipelineDefinition.resolutionMode,
        CicdIntegrationSourceResolutionMode.byId,
      );
    });

    test('latest only when useLatest is true for upstream artifacts', () async {
      final evidence = ReleaseEvidenceTestFixtures.validBundle();
      final supplyChain =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      reProvider.latestBundle = evidence;
      rscProvider.latestSnapshot = supplyChain;

      final withLatest = CicdIntegrationRequest(
        requestId: 'resolver-latest',
        projectId: CicdIntegrationOperationalFixtures.projectId,
        releaseId: CicdIntegrationOperationalFixtures.releaseId,
        requestedAt: CicdIntegrationOperationalFixtures.referenceTime,
        useLatest: true,
        pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
        pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
        deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
      );
      final withoutLatest = withLatest.copyWith(useLatest: false);

      final resolvedLatest = await resolver.resolveAll(withLatest);
      final resolvedNone = await resolver.resolveAll(withoutLatest);

      expect(reProvider.latestCalls, 1);
      expect(rscProvider.latestCalls, 1);
      expect(resolvedLatest.releaseEvidenceBundle.isAvailable, isTrue);
      expect(resolvedLatest.releaseSupplyChainSnapshot.isAvailable, isTrue);
      expect(
        resolvedNone.releaseEvidenceBundle.state,
        CicdIntegrationSourceState.notRequested,
      );
      expect(
        resolvedNone.releaseSupplyChainSnapshot.state,
        CicdIntegrationSourceState.notRequested,
      );
    });

    test('missing byId does not fall back to latest implicitly', () async {
      reProvider.latestBundle = ReleaseEvidenceTestFixtures.validBundle();

      final request = CicdIntegrationRequest(
        requestId: 'resolver-missing-by-id',
        projectId: CicdIntegrationOperationalFixtures.projectId,
        requestedAt: CicdIntegrationOperationalFixtures.referenceTime,
        pipelineDefinitionId: 'missing-def',
        pipelineIntegrationPolicyId: PipelineIntegrationPolicyV1.policyId,
        pipelineExecutionPolicyId: PipelineExecutionPolicyV1.policyId,
        deploymentIntegrationPolicyId: DeploymentIntegrationPolicyV1.policyId,
      );

      final registry = CicdIntegrationArtifactRegistry();
      final resolverWithRegistry = CicdIntegrationSourceResolver(
        releaseEvidenceProvider: reProvider,
        releaseSupplyChainProvider: rscProvider,
        artifactRegistry: registry,
        pipelineIntegrationPolicyRegistry: PipelineIntegrationPolicyRegistry()
          ..register(PipelineIntegrationPolicyV1.create())
          ..freeze(),
        pipelineExecutionPolicyRegistry: PipelineExecutionPolicyRegistry()
          ..register(PipelineExecutionPolicyV1.create())
          ..freeze(),
        deploymentIntegrationPolicyRegistry:
            DeploymentIntegrationPolicyRegistry()
              ..register(DeploymentIntegrationPolicyV1.create())
              ..freeze(),
      );

      final sources = await resolverWithRegistry.resolveAll(request);
      expect(reProvider.latestCalls, 0);
      expect(sources.pipelineDefinition.isAvailable, isFalse);
    });

    test('resolver never calls origin evaluate or publish', () async {
      await resolver.resolveAll(
        CicdIntegrationOperationalFixtures.passingRequest(),
        injectedPipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        injectedPipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        injectedDeploymentIntegrationPolicy:
            DeploymentIntegrationPolicyV1.create(),
      );
      expect(reProvider.evaluateCalls, 0);
      expect(reProvider.evaluateAndPublishCalls, 0);
      expect(reProvider.publishCalls, 0);
      expect(rscProvider.evaluateCalls, 0);
      expect(rscProvider.evaluateAndPublishCalls, 0);
      expect(rscProvider.publishCalls, 0);
    });

    test('injected upstream artifacts skip provider latest', () async {
      reProvider.latestBundle = ReleaseEvidenceTestFixtures.validBundle();
      rscProvider.latestSnapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();

      await resolver.resolveAll(
        CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: ReleaseEvidenceTestFixtures.validBundle(),
          releaseSupplyChainSnapshot:
              ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot(),
        ),
        injectedPipelineIntegrationPolicy: PipelineIntegrationPolicyV1.create(),
        injectedPipelineExecutionPolicy: PipelineExecutionPolicyV1.create(),
        injectedDeploymentIntegrationPolicy:
            DeploymentIntegrationPolicyV1.create(),
      );

      expect(reProvider.latestCalls, 0);
      expect(rscProvider.latestCalls, 0);
      expect(reProvider.evaluateCalls, 0);
      expect(rscProvider.evaluateCalls, 0);
    });
  });
}
