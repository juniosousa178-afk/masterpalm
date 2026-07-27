import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain collector audit', () {
    const collector = ReleaseSupplyChainCollector();

    ResolvedReleaseSupplyChainSources buildSources({
      required dynamic qg,
      required dynamic rg,
      required dynamic re,
    }) {
      return ResolvedReleaseSupplyChainSources(
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
        releaseDecisionSnapshot: ResolvedReleaseSupplyChainSource(
          sourceType: ReleaseSupplyChainSourceType.releaseGovernance,
          resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
          state: ReleaseSupplyChainSourceState.available,
          resolvedArtifact: rg,
        ),
        releaseEvidenceBundle: ResolvedReleaseSupplyChainSource(
          sourceType: ReleaseSupplyChainSourceType.releaseEvidence,
          resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
          state: ReleaseSupplyChainSourceState.available,
          resolvedArtifact: re,
        ),
        supplyChainPolicy: rscNotRequested(),
        distributionPolicy: rscNotRequested(),
        compliancePolicy: rscNotRequested(),
        sourceReferences: const [],
        resolutionSummary: const ReleaseSupplyChainSourceResolutionSummary(
          resolvedSources: [],
          unresolvedSources: [],
          injectedSources: [],
        ),
      );
    }

    test('deduplicates artifacts by artifactId', () {
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final reBundle = ReleaseEvidenceTestFixtures.validBundle();

      final context = ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null, re: reBundle),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
      final collected = collector.collect(context);
      final ids = collected.artifacts.map((e) => e.artifactId).toList();
      expect(ids, equals(ids.toSet().toList()..sort()));
    });

    test('does not duplicate QG fingerprint in multiple artifacts for same id',
        () {
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final context = ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null, re: null),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
      final collected = collector.collect(context);
      final qgArtifacts = collected.artifacts
          .where(
            (e) => e.artifactId == qg.metadata.qualityGateSnapshotId,
          )
          .toList();
      expect(qgArtifacts, hasLength(1));
    });

    test('absent sources produce no artifacts for that type', () {
      final context = ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(),
        sources: buildSources(qg: null, rg: null, re: null),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
      final collected = collector.collect(context);
      expect(collected.qualityGateSnapshot, isNull);
      expect(collected.releaseDecisionSnapshot, isNull);
      expect(collected.releaseEvidenceBundle, isNull);
      expect(collected.artifacts, isEmpty);
    });

    test('artifacts reference fingerprints not payloads', () {
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final context = ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null, re: null),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
      final collected = collector.collect(context);
      for (final artifact in collected.artifacts) {
        expect(artifact.fingerprint, isNotEmpty);
        expect(artifact.fingerprint, qg.metadata.qualityGateFingerprint);
      }
    });

    test('collector does not recalculate source fingerprints', () {
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final originalFp = qg.metadata.qualityGateFingerprint;
      final context = ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
        ),
        sources: buildSources(qg: qg, rg: null, re: null),
        supplyChainPolicy: SupplyChainPolicyV1.create(),
        distributionPolicy: DistributionPolicyV1.create(),
        compliancePolicy: CompliancePolicyV1.create(),
      );
      final collected = collector.collect(context);
      expect(
        collected.qualityGateSnapshot!.metadata.qualityGateFingerprint,
        originalFp,
      );
    });
  });
}
