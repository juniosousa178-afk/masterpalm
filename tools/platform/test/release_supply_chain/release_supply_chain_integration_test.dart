import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/compliance_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/dashboard_section_context.dart';
import 'package:masterpalm_platform/dashboard/builders/sbom_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/supply_chain_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/mappers/release_supply_chain_history_mapper.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/interfaces/release_supply_chain_provider.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';
import 'package:masterpalm_platform/models/history/history_artifact_type.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_operational_enums.dart';
import 'package:masterpalm_platform/models/release_supply_chain/release_supply_chain_result.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/compliance_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/distribution_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/policies/supply_chain_policy_v1.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_collector.dart';
import 'package:masterpalm_platform/release_supply_chain/release_supply_chain_source_resolver.dart';
import 'package:masterpalm_platform/release_supply_chain/resolved_release_supply_chain_sources.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/release_supply_chain_report_source.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain integration', () {
    late ReleaseSupplyChainProvider supplyChainProvider;
    late ReleaseEvidenceProvider evidenceProvider;
    late ReleaseGovernanceProvider governanceProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      supplyChainProvider = core.releaseSupplyChain();
      evidenceProvider = core.releaseEvidence();
      governanceProvider = core.releaseGovernance();
    });

    Future<dynamic> evaluatePublishedSnapshot() async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluateAndPublish(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final result = await supplyChainProvider.evaluateAndPublish(
        ReleaseSupplyChainTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
          publish: true,
        ),
      );
      expect(result.snapshot, isNotNull);
      return result.snapshot!;
    }

    test('source resolver prefers injected snapshots over byId', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final resolver = ReleaseSupplyChainSourceResolver(
        qualityGateProvider: core.qualityGate(),
        releaseGovernanceProvider: core.releaseGovernance(),
        releaseEvidenceProvider: core.releaseEvidence(),
      );
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final request = ReleaseSupplyChainTestFixtures.passingRequest(
        qualityGateSnapshot: qg,
      );

      final sources = await resolver.resolveAll(
        request,
        injectedSupplyChainPolicy: SupplyChainPolicyV1.create(),
        injectedDistributionPolicy: DistributionPolicyV1.create(),
        injectedCompliancePolicy: CompliancePolicyV1.create(),
      );

      expect(sources.qualityGateSnapshot.isAvailable, isTrue);
      expect(
        sources.qualityGateSnapshot.resolutionMode,
        ReleaseSupplyChainSourceResolutionMode.injected,
      );
      expect(sources.resolutionSummary.injectedSources, isNotEmpty);
    });

    test('collector locates artifacts without rebuilding snapshots', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final reResult = await evidenceProvider.evaluate(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      final qg = ReleaseSupplyChainTestFixtures.passingQualityGateSnapshot();
      final qgFingerprint = qg.metadata.qualityGateFingerprint;

      final context = ReleaseSupplyChainEvaluationContext(
        request: ReleaseSupplyChainTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
          releaseDecisionSnapshot: rgResult.snapshot,
          releaseEvidenceBundle: reResult.bundle,
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
          releaseDecisionSnapshot: ResolvedReleaseSupplyChainSource(
            sourceType: ReleaseSupplyChainSourceType.releaseGovernance,
            resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
            state: ReleaseSupplyChainSourceState.available,
            resolvedArtifact: rgResult.snapshot,
          ),
          releaseEvidenceBundle: ResolvedReleaseSupplyChainSource(
            sourceType: ReleaseSupplyChainSourceType.releaseEvidence,
            resolutionMode: ReleaseSupplyChainSourceResolutionMode.injected,
            state: ReleaseSupplyChainSourceState.available,
            resolvedArtifact: reResult.bundle,
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

      const collector = ReleaseSupplyChainCollector();
      final collected = collector.collect(context);

      expect(collected.qualityGateSnapshot, isNotNull);
      expect(
        collected.qualityGateSnapshot!.metadata.qualityGateFingerprint,
        qgFingerprint,
      );
      expect(collected.releaseDecisionSnapshot, isNotNull);
      expect(collected.releaseEvidenceBundle, isNotNull);
    });

    test('report source consumes published snapshot only', () async {
      final snapshot = await evaluatePublishedSnapshot();
      const source = ReleaseSupplyChainReportSource();
      final data = source.fromSnapshot(snapshot);

      expect(data.snapshotId, snapshot.metadata.supplyChainSnapshotId);
      expect(data.fingerprint, snapshot.fingerprint);
      expect(data.projectId, snapshot.metadata.projectId);
    });

    test('history mapper maps snapshot to artifact', () async {
      final snapshot = await evaluatePublishedSnapshot();
      const mapper = ReleaseSupplyChainHistoryMapper();
      final artifact = mapper.fromMap(snapshot.toJson());

      expect(artifact.artifactType, HistoryArtifactType.releaseSupplyChain);
      expect(artifact.artifactId, snapshot.metadata.supplyChainSnapshotId);
    });

    test('dashboard sections consume injected snapshot without evaluate', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final request = DashboardRequest(
        projectId: ReleaseSupplyChainTestFixtures.projectId,
        createdAt: ReleaseSupplyChainTestFixtures.referenceTime,
        referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
        releaseSupplyChainSnapshot: snapshot,
        requestedSections: {
          DashboardSectionType.supplyChain,
          DashboardSectionType.sbom,
          DashboardSectionType.compliance,
        },
      );
      final sources = DashboardResolvedSources(releaseSupplyChain: snapshot);
      final context = DashboardSectionBuildContext(
        request: request,
        sources: sources,
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );

      final supplyChain = const SupplyChainSectionBuilder().build(context);
      final sbom = const SbomSectionBuilder().build(context);
      final compliance = const ComplianceSectionBuilder().build(context);

      expect(supplyChain.availability, DashboardAvailability.available);
      expect(sbom.availability, DashboardAvailability.available);
      expect(compliance.availability, DashboardAvailability.available);
    });

    test('platform bootstrap registers supply chain after evidence', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.releaseSupplyChain(), isNotNull);
      expect(core.releaseEvidence(), isNotNull);
    });

    test('report engine generates releaseSupplyChain report from snapshot',
        () async {
      final snapshot = await evaluatePublishedSnapshot();
      final engine = ReportEngine();
      final result = await engine.generate(
        ReportRequest(
          reportType: ReportType.releaseSupplyChain,
          projectId: ReleaseSupplyChainTestFixtures.projectId,
          releaseSupplyChainSnapshot: snapshot.toJson(),
        ),
      );

      expect(result.document.sections, isNotEmpty);
    });
  });
}
