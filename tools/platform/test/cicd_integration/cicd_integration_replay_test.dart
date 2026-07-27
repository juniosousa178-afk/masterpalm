import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/cicd_integration/cicd_integration_canonical_serializer.dart';
import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/interfaces/cicd_integration_provider.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_operational_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/cicd_integration_snapshot.dart';
import 'package:masterpalm_platform/models/cicd_integration/deployment_models.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_enums.dart';
import 'package:masterpalm_platform/models/cicd_integration/pipeline_models.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';
import 'support/pipeline_test_fixtures.dart';

void main() {
  group('CI/CD Integration replay', () {
    late CicdIntegrationProvider provider;
    const serializer = CicdIntegrationCanonicalSerializer();

    setUp(() {
      provider =
          PlatformBootstrap.forRepo(Directory.current.path).cicdIntegration();
    });

    Future<(dynamic, dynamic)> buildUpstream() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rgResult = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final reResult = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rgResult.snapshot,
            ),
          );
      final rscResult = await core.releaseSupplyChain().evaluate(
            ReleaseSupplyChainTestFixtures.passingRequest(
              releaseDecisionSnapshot: rgResult.snapshot,
              releaseEvidenceBundle: reResult.bundle,
            ),
          );
      return (reResult.bundle, rscResult.snapshot);
    }

    test('re-evaluate same inputs yields identical snapshot fingerprint',
        () async {
      final (evidence, supplyChain) = await buildUpstream();
      final request = CicdIntegrationOperationalFixtures.passingRequest(
        releaseEvidenceBundle: evidence,
        releaseSupplyChainSnapshot: supplyChain,
      );

      final first = await provider.evaluate(request);
      final second = await provider.evaluate(request);

      expect(
        first.snapshot!.metadata.cicdIntegrationSnapshotId,
        second.snapshot!.metadata.cicdIntegrationSnapshotId,
      );
      expect(first.snapshot!.fingerprint, second.snapshot!.fingerprint);
    });

    test('replay preserves component fingerprints', () async {
      final (evidence, supplyChain) = await buildUpstream();
      final request = CicdIntegrationOperationalFixtures.passingRequest(
        releaseEvidenceBundle: evidence,
        releaseSupplyChainSnapshot: supplyChain,
      );

      final first = (await provider.evaluate(request)).snapshot!;
      final second = (await provider.evaluate(request)).snapshot!;

      expect(second.metadata.pipelineFingerprint,
          first.metadata.pipelineFingerprint);
      expect(second.metadata.executionFingerprint,
          first.metadata.executionFingerprint);
      expect(
        second.metadata.deploymentPlanFingerprint,
        first.metadata.deploymentPlanFingerprint,
      );
      expect(
        second.metadata.releaseEvidenceBundleId,
        first.metadata.releaseEvidenceBundleId,
      );
      expect(
        second.metadata.releaseSupplyChainSnapshotId,
        first.metadata.releaseSupplyChainSnapshotId,
      );
    });

    test('canonical serializer fingerprints are stable on replay', () async {
      final (evidence, supplyChain) = await buildUpstream();
      final request = CicdIntegrationOperationalFixtures.passingRequest(
        releaseEvidenceBundle: evidence,
        releaseSupplyChainSnapshot: supplyChain,
      );

      final first = (await provider.evaluate(request)).snapshot!;
      final second = (await provider.evaluate(request)).snapshot!;

      expect(
        serializer.snapshotFingerprint(second),
        serializer.snapshotFingerprint(first),
      );
      expect(
        serializer.pipelineDefinitionFingerprint(second.pipelineDefinition!),
        serializer.pipelineDefinitionFingerprint(first.pipelineDefinition!),
      );
      expect(
        serializer.pipelineExecutionFingerprint(second.pipelineExecution!),
        serializer.pipelineExecutionFingerprint(first.pipelineExecution!),
      );
      expect(
        serializer.deploymentPlanFingerprint(second.deploymentPlan!),
        serializer.deploymentPlanFingerprint(first.deploymentPlan!),
      );
    });

    test('toJson/fromJson round-trip preserves snapshot identity', () async {
      final snapshot =
          (await evaluatePassingSnapshot(provider: provider)).snapshot!;
      final restored = CicdIntegrationSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );

      expect(
        restored.metadata.cicdIntegrationSnapshotId,
        snapshot.metadata.cicdIntegrationSnapshotId,
      );
      expect(restored.fingerprint, snapshot.fingerprint);
    });

    test('100 cycles json roundtrip preserve fingerprint', () async {
      final snapshot =
          (await evaluatePassingSnapshot(provider: provider)).snapshot!;
      final originalFp = serializer.snapshotFingerprint(snapshot);

      for (var i = 0; i < 100; i++) {
        final restored = CicdIntegrationSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        );
        expect(serializer.snapshotFingerprint(restored), originalFp);
      }
    });

    test('component round-trips preserve fingerprints', () async {
      final snapshot =
          (await evaluatePassingSnapshot(provider: provider)).snapshot!;

      final definition = PipelineDefinition.fromJson(
        jsonDecode(jsonEncode(snapshot.pipelineDefinition!.toJson()))
            as Map<String, dynamic>,
      );
      final execution = PipelineExecution.fromJson(
        jsonDecode(jsonEncode(snapshot.pipelineExecution!.toJson()))
            as Map<String, dynamic>,
      );
      final plan = DeploymentPlan.fromJson(
        jsonDecode(jsonEncode(snapshot.deploymentPlan!.toJson()))
            as Map<String, dynamic>,
      );

      expect(definition.fingerprint, snapshot.pipelineDefinition!.fingerprint);
      expect(execution.fingerprint, snapshot.pipelineExecution!.fingerprint);
      expect(plan.fingerprint, snapshot.deploymentPlan!.fingerprint);
    });

    group('scenario replays', () {
      test('complete snapshot scenario', () async {
        final (evidence, supplyChain) = await buildUpstream();
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(
            releaseEvidenceBundle: evidence,
            releaseSupplyChainSnapshot: supplyChain,
          ),
        );
        expect(result.snapshot!.status, CicdIntegrationSnapshotStatus.complete);
        expect(result.snapshot!.deploymentPlan, isNotNull);
      });

      test('partial snapshot without deployment scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.partialRequest(),
        );
        expect(result.snapshot!.status, CicdIntegrationSnapshotStatus.partial);
        expect(result.snapshot!.deploymentPlan, isNull);
      });

      test('failed execution scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.failedExecutionRequest(),
        );
        expect(
          result.snapshot!.pipelineExecution!.status,
          PipelineStatus.failed,
        );
      });

      test('deployment present scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(),
        );
        expect(result.snapshot!.deploymentPlan, isNotNull);
        expect(result.snapshot!.deploymentResult, isNotNull);
      });

      test('deployment absent scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.partialRequest(),
        );
        expect(result.snapshot!.deploymentPlan, isNull);
        expect(result.snapshot!.deploymentResult, isNull);
      });

      test('upstream evidence and supply chain present scenario', () async {
        final (evidence, supplyChain) = await buildUpstream();
        final evidenceFp = evidence!.fingerprint;
        final supplyChainFp = supplyChain!.fingerprint;
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(
            releaseEvidenceBundle: evidence,
            releaseSupplyChainSnapshot: supplyChain,
          ),
        );
        expect(result.snapshot!.metadata.releaseEvidenceBundleId, isNotNull);
        expect(
            result.snapshot!.metadata.releaseSupplyChainSnapshotId, isNotNull);
        expect(evidence.fingerprint, evidenceFp);
        expect(supplyChain.fingerprint, supplyChainFp);
      });

      test('upstream absent scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.passingRequest(),
        );
        expect(result.snapshot!.metadata.releaseEvidenceBundleId, isNull);
        expect(result.snapshot!.metadata.releaseSupplyChainSnapshotId, isNull);
      });

      test('projectId mismatch scenario preserves limitation', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.projectIdMismatchRequest(),
        );
        expect(
          result.limitations
              .any((l) => l.limitationId == 'project-mismatch-evidence'),
          isTrue,
        );
      });

      test('wrong definition ref scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.wrongDefinitionRefRequest(),
        );
        expect(
          result.limitations.any(
            (l) => l.limitationId == 'execution-definition-mismatch',
          ),
          isTrue,
        );
      });

      test('missing definition scenario', () async {
        final result = await provider.evaluate(
          CicdIntegrationOperationalFixtures.missingDefinitionRequest(),
        );
        expect(result.limitations, isNotEmpty);
        expect(result.snapshot!.pipelineDefinition, isNull);
      });
    });
  });
}
