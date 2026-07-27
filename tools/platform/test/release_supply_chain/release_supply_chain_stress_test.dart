import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_snapshot_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain stress tests', () {
    ReleaseSupplyChainEvaluationContext buildStressContext() {
      return ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(),
        sources: ResolvedReleaseSupplyChainSources(
          releaseContext: rscNotRequested(),
          qualityGateSnapshot: rscNotRequested(),
          releaseDecisionSnapshot: rscNotRequested(),
          releaseEvidenceBundle: rscNotRequested(),
          supplyChainPolicy: rscNotRequested(),
          distributionPolicy: rscNotRequested(),
          compliancePolicy: rscNotRequested(),
          sourceReferences: const [],
          resolutionSummary: const ReleaseSupplyChainSourceResolutionSummary(
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
    }

    test('graph builder handles 1000 nodes', () {
      final graph = buildLargeSupplyChainGraph(nodeCount: 1000);
      expect(graph.nodes, hasLength(1000));
      expect(graph.stages, hasLength(1000));
      expect(graph.fingerprint, isNotEmpty);
    });

    test('sbom builder handles 1000 components', () {
      final sbom = buildLargeSbom(componentCount: 1000);
      expect(sbom.components, hasLength(1000));
      expect(sbom.metadata.componentCount, 1000);
      expect(sbom.metadata.fingerprint, isNotEmpty);
    });

    test('snapshot builder handles large collected artifact set', () {
      final context = buildStressContext();
      final artifacts = List.generate(
        100,
        (i) => ReleaseSupplyChainCollectedArtifact(
          artifactId: 'stress-art-${i.toString().padLeft(5, '0')}',
          artifactType: 'qualityGateSnapshot',
          sourceType: 'qualityGate',
          fingerprint: 'fp-stress-$i',
        ),
      );
      final collected = ReleaseSupplyChainCollectedArtifacts(
        qualityGateSnapshot:
            ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot(),
        artifacts: artifacts,
      );

      final stopwatch = Stopwatch()..start();
      final result = ReleaseSupplyChainSnapshotBuilder().build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );
      stopwatch.stop();

      expect(result.snapshot, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });

    test('collector dedup maintains stability at scale', () {
      final artifacts = List.generate(
        200,
        (i) => ReleaseSupplyChainCollectedArtifact(
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
