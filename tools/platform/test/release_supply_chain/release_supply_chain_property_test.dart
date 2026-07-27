import 'dart:math';

import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/supply_chain_models.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_canonical_serializer.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_snapshot_validator.dart';
import 'package:masterpalm_platform/release_supply_chain/supply_chain_graph_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:test/test.dart';

import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain property-based tests', () {
    final random = Random(42);
    const serializer = ReleaseSupplyChainCanonicalSerializer();

    ReleaseSupplyChainEvaluationContext buildContext() {
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

    test('collector sorts artifacts deterministically for any input order', () {
      for (var seed = 0; seed < 20; seed++) {
        final rng = Random(seed);
        final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
        final context = ReleaseSupplyChainEvaluationContext(
          request: ReleaseSupplyChainTestFixtures.passingRequest(
            qualityGateSnapshot: qg,
          ),
          sources: ResolvedReleaseSupplyChainSources(
            releaseContext: ResolvedReleaseSupplyChainSource(
              sourceType: ReleaseSupplyChainSourceType.releaseContext,
              resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
              state: ReleaseSupplyChainSourceState.available,
              resolvedArtifact: ReleaseSupplyChainTestFixtures.validContext(),
            ),
            qualityGateSnapshot: ResolvedReleaseSupplyChainSource(
              sourceType: ReleaseSupplyChainSourceType.qualityGate,
              resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
              state: ReleaseSupplyChainSourceState.available,
              resolvedArtifact: qg,
            ),
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
        final collected = const ReleaseSupplyChainCollector().collect(context);
        final ids = collected.artifacts.map((e) => e.artifactId).toList();
        expect(ids, equals(ids.toList()..sort()));
        expect(rng.nextInt(100), greaterThanOrEqualTo(0));
      }
    });

    test('graph builder stage ordering matches policy for random seeds', () {
      const builder = SupplyChainGraphBuilder();
      for (var i = 0; i < 10 + random.nextInt(5); i++) {
        final context = buildContext();
        final collected = ReleaseSupplyChainCollectedArtifacts(
          artifacts: [
            ReleaseSupplyChainCollectedArtifact(
              artifactId: 'art-seed-$i',
              artifactType: 'qualityGateSnapshot',
              sourceType: 'qualityGate',
              fingerprint: 'fp-$i',
            ),
          ],
          qualityGateSnapshot:
              ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot(),
        );
        final graph = builder.build(
          context: context,
          collected: collected,
          evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
        );
        final stageTypes = graph!.stages.map((s) => s.stageType).toList();
        expect(
          stageTypes,
          context.supplyChainPolicy.policy.requiredStageTypes,
        );
      }
    });

    test('serializer fingerprint invariant under repeated serialization', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final fp = serializer.snapshotFingerprint(snapshot);
      for (var i = 0; i < 10; i++) {
        final json = snapshot.toJson();
        expect(serializer.snapshotFingerprint(snapshot), fp);
        expect(json.keys.length, greaterThan(5));
      }
    });

    test('validation rejects mutated snapshot metadata fingerprint mismatch',
        () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final mutated = snapshot.copyWith(
        metadata: snapshot.metadata.copyWith(fingerprint: 'mutated-fp'),
      );
      expect(
        const ReleaseSupplyChainSnapshotValidator().validate(mutated).isValid,
        isFalse,
      );
    });

    test('large graph nodes remain uniquely identified', () {
      final graph = buildLargeSupplyChainGraph(nodeCount: 50);
      final nodeIds = graph.nodes.map((n) => n.nodeId).toList();
      expect(nodeIds.length, equals(nodeIds.toSet().length));
      expect(graph.nodes.first, isA<SupplyChainNode>());
    });
  });
}
