import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/core/platform_core.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_request.dart';
import 'package:masterpalm_platform/cicd_integration/cicd_integration_exceptions.dart';
import 'package:masterpalm_platform/cicd_integration/policies/pipeline_integration_policy_v1.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cicd_integration_operational_fixtures.dart';

void main() {
  group('CicdIntegrationProvider', () {
    late PlatformCore core;
    late CicdIntegrationProvider cicdProvider;
    late ReleaseEvidenceProvider evidenceProvider;
    late ReleaseSupplyChainProvider supplyChainProvider;

    setUp(() {
      core = PlatformBootstrap.forRepo(Directory.current.path);
      cicdProvider = core.cicdIntegration();
      evidenceProvider = core.releaseEvidence();
      supplyChainProvider = core.releaseSupplyChain();
    });

    test('PlatformCore resolves CicdIntegrationProvider', () {
      expect(core.cicdIntegration(), isA<CicdIntegrationProvider>());
    });

    Future<(dynamic, dynamic)> buildUpstreamArtifacts() async {
      final rgResult = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final rscResult = await supplyChainProvider.evaluate(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
        ),
      );
      return (reResult.bundle, rscResult.snapshot);
    }

    test('evaluate builds snapshot from injected sources', () async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final result = await cicdProvider.evaluate(
        CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        ),
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.pipelineDefinition, isNotNull);
      expect(result.snapshot!.pipelineExecution, isNotNull);
      expect(result.snapshot!.deploymentPlan, isNotNull);
      expect(result.sourceResolutionSummary?.injectedSources, isNotEmpty);
    });

    test('evaluateAndPublish stores snapshot idempotently', () async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final request = CicdIntegrationOperationalFixtures.passingRequest(
        releaseEvidenceBundle: evidence,
        releaseSupplyChainSnapshot: supplyChain,
      );

      final first = await cicdProvider.evaluateAndPublish(request);
      expect(first.snapshot, isNotNull);
      expect(
        first.publicationStatus,
        CicdIntegrationPublicationStatus.published,
      );

      final loaded = await cicdProvider.load(
        first.snapshot!.metadata.cicdIntegrationSnapshotId,
      );
      expect(loaded, isNotNull);
      expect(loaded!.fingerprint, first.snapshot!.fingerprint);

      final second = await cicdProvider.evaluateAndPublish(request);
      expect(
        second.publicationStatus,
        CicdIntegrationPublicationStatus.skipped,
      );
      expect(
        second.snapshot!.metadata.cicdIntegrationSnapshotId,
        first.snapshot!.metadata.cicdIntegrationSnapshotId,
      );
    });

    test('snapshot fingerprint is deterministic across evaluations', () async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final request = CicdIntegrationOperationalFixtures.passingRequest(
        releaseEvidenceBundle: evidence,
        releaseSupplyChainSnapshot: supplyChain,
      );

      final first = await cicdProvider.evaluate(request);
      final second = await cicdProvider.evaluate(request);

      expect(first.snapshot!.fingerprint, second.snapshot!.fingerprint);
    });

    test('missing policy id without registry match throws', () async {
      final request = CicdIntegrationRequest(
        requestId: 'missing-policy-req',
        projectId: CicdIntegrationOperationalFixtures.projectId,
        requestedAt: CicdIntegrationOperationalFixtures.referenceTime,
        pipelineIntegrationPolicyId: 'nonexistent-policy',
        pipelineDefinition: CicdIntegrationOperationalFixtures.passingRequest()
            .pipelineDefinition,
      );

      expect(
        () => cicdProvider.evaluate(request),
        throwsA(isA<CicdIntegrationPolicyNotFoundException>()),
      );
    });

    test('default policy resolves to pipeline-integration-v1', () async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final result = await cicdProvider.evaluate(
        CicdIntegrationRequest(
          requestId: CicdIntegrationOperationalFixtures.requestId,
          projectId: CicdIntegrationOperationalFixtures.projectId,
          releaseId: CicdIntegrationOperationalFixtures.releaseId,
          requestedAt: CicdIntegrationOperationalFixtures.referenceTime,
          pipelineDefinition:
              CicdIntegrationOperationalFixtures.passingRequest()
                  .pipelineDefinition,
          pipelineExecution: CicdIntegrationOperationalFixtures.passingRequest()
              .pipelineExecution,
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        ),
      );

      expect(
        result.snapshot?.metadata.pipelineIntegrationPolicyId,
        PipelineIntegrationPolicyV1.policyId,
      );
    });

    test('PlatformCore cicdIntegrationEvaluate delegates to provider',
        () async {
      final (evidence, supplyChain) = await buildUpstreamArtifacts();
      final result = await core.cicdIntegrationEvaluate(
        CicdIntegrationOperationalFixtures.passingRequest(
          releaseEvidenceBundle: evidence,
          releaseSupplyChainSnapshot: supplyChain,
        ),
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.pipelineDefinition, isNotNull);
    });
  });
}
