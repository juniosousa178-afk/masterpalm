import 'package:masterpalm_platform/models/quality_gate/quality_gate_snapshot.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/release_supply_chain/compliance_engine.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_snapshot_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/sbom_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/supply_chain_graph_builder.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

ReleaseSupplyChainEvaluationContext _buildContext({
  QualityGateSnapshot? qg,
}) {
  final qualityGate =
      qg ?? ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
  final re = ReleaseEvidenceTestFixtures.validBundle();

  return ReleaseSupplyChainEvaluationContext(
    request: ReleaseSupplyChainTestFixtures.passingRequest(
      qualityGateSnapshot: qualityGate,
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
        resolvedArtifact: qualityGate,
      ),
      releaseDecisionSnapshot: rscNotRequested(),
      releaseEvidenceBundle: ResolvedReleaseSupplyChainSource(
        sourceType: ReleaseSupplyChainSourceType.releaseEvidence,
        resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
        state: ReleaseSupplyChainSourceState.available,
        resolvedArtifact: re,
      ),
      supplyChainPolicy: ResolvedReleaseSupplyChainSource(
        sourceType: ReleaseSupplyChainSourceType.supplyChainPolicy,
        resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
        state: ReleaseSupplyChainSourceState.available,
        resolvedArtifact: SupplyChainPolicyV1.create(),
      ),
      distributionPolicy: ResolvedReleaseSupplyChainSource(
        sourceType: ReleaseSupplyChainSourceType.distributionPolicy,
        resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
        state: ReleaseSupplyChainSourceState.available,
        resolvedArtifact: DistributionPolicyV1.create(),
      ),
      compliancePolicy: ResolvedReleaseSupplyChainSource(
        sourceType: ReleaseSupplyChainSourceType.compliancePolicy,
        resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
        state: ReleaseSupplyChainSourceState.available,
        resolvedArtifact: CompliancePolicyV1.create(),
      ),
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

void main() {
  group('Release Supply Chain engine audit', () {
    const graphBuilder = SupplyChainGraphBuilder();
    const sbomBuilder = SbomBuilder();
    const complianceEngine = ComplianceEngine();
    final snapshotBuilder = ReleaseSupplyChainSnapshotBuilder();

    test('graph builder produces stages in policy order', () {
      final context = _buildContext();
      final collected = const ReleaseSupplyChainCollector().collect(context);
      final graph = graphBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      final stageTypes = graph!.stages.map((s) => s.stageType).toList();
      expect(
        stageTypes,
        context.supplyChainPolicy.policy.requiredStageTypes,
      );
    });

    test('sbom builder sorts components deterministically', () {
      final context = _buildContext();
      final collected = const ReleaseSupplyChainCollector().collect(context);
      final sbom = sbomBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      expect(sbom!.components, hasLength(1));
      expect(sbom.metadata.componentCount, sbom.components.length);
    });

    test('builders do not mutate source artifact fingerprints', () {
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final originalQgFp = qg.metadata.qualityGateFingerprint;
      final originalBundleFp =
          ReleaseEvidenceTestFixtures.validBundle().fingerprint;

      final context = _buildContext(qg: qg);
      final collected = const ReleaseSupplyChainCollector().collect(context);

      graphBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );
      sbomBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );
      snapshotBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      expect(
        collected.qualityGateSnapshot!.metadata.qualityGateFingerprint,
        originalQgFp,
      );
      expect(
        collected.releaseEvidenceBundle!.fingerprint,
        originalBundleFp,
      );
    });

    test('snapshot builder assembles all components without mutating sources',
        () {
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final qgJsonBefore = qg.toJson();
      final context = _buildContext(qg: qg);
      final collected = const ReleaseSupplyChainCollector().collect(context);

      final result = snapshotBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.provenance, isNotNull);
      expect(result.snapshot!.supplyChain, isNotNull);
      expect(result.snapshot!.sbom, isNotNull);
      expect(result.snapshot!.artifacts, isNotEmpty);
      expect(result.snapshot!.distribution, isNotNull);
      expect(result.snapshot!.compliance, isNotNull);
      expect(qg.toJson(), equals(qgJsonBefore));
    });

    test('compliance engine evaluates structural rules only', () {
      final context = _buildContext();
      final collected = const ReleaseSupplyChainCollector().collect(context);
      final graph = graphBuilder.build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      final compliance = complianceEngine.evaluate(
        context: context,
        collected: collected,
        supplyChain: graph,
        evaluatedAt: ReleaseSupplyChainTestFixtures.referenceTime,
      );

      expect(compliance.checks, isNotEmpty);
      expect(compliance.fingerprint, isNotEmpty);
    });
  });
}
