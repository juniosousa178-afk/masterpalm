import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/compliance_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/sbom_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/supply_chain_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_composer.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/mappers/release_supply_chain_history_mapper.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';
import 'package:masterpalm_platform/models/history/history_artifact_type.dart';
import 'package:masterpalm_platform/models/history/history_change_type.dart';
import 'package:masterpalm_platform/models/history/history_metadata.dart';
import 'package:masterpalm_platform/models/history/history_snapshot.dart';
import 'package:masterpalm_platform/models/history/history_snapshot_status.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/release_supply_chain_report_source.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_supply_chain_hardening_helpers.dart';
import 'support/release_supply_chain_test_fixtures.dart';

void main() {
  group('Release Supply Chain integration audits', () {
    Future<dynamic> publishedSnapshot() async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rg = await core.releaseGovernance().evaluate(
            ReleaseGovernanceTestFixtures.passingRequest(),
          );
      final re = await core.releaseEvidence().evaluate(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
            ),
          );
      final published = await core.releaseSupplyChain().evaluateAndPublish(
            ReleaseSupplyChainTestFixtures.passingRequest(
              releaseDecisionSnapshot: rg.snapshot,
              releaseEvidenceBundle: re.bundle,
            ),
          );
      return published.snapshot!;
    }

    test('report full snapshot generates sections', () async {
      final snapshot = await publishedSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseSupplyChain,
          projectId: snapshot.metadata.projectId,
          releaseSupplyChainSnapshot: snapshot.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
      final input =
          const ReleaseSupplyChainReportSource().fromSnapshot(snapshot);
      expect(input.snapshotId, snapshot.metadata.supplyChainSnapshotId);
      expect(input.fingerprint, snapshot.fingerprint);
    });

    test('report partial snapshot still renders', () async {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseSupplyChain,
          projectId: snapshot.metadata.projectId,
          releaseSupplyChainSnapshot: snapshot.toJson(),
        ),
      );
      expect(
          report.document.metadata.reportType, ReportType.releaseSupplyChain);
    });

    test('history diff is deterministic for same inputs', () async {
      const mapper = ReleaseSupplyChainHistoryMapper();
      final snapshot = await publishedSnapshot();
      final a1 = mapper.fromMap(snapshot.toJson());
      final a2 = mapper.fromMap(snapshot.toJson());
      expect(a1.fingerprint, a2.fingerprint);

      final changes = mapper.compare(snapshot, snapshot);
      expect(changes, isEmpty);
    });

    test('history comparator replays equivalent snapshots', () async {
      const mapper = ReleaseSupplyChainHistoryMapper();
      final snapshot = await publishedSnapshot();
      final artifact = mapper.fromMap(snapshot.toJson());
      final from = HistorySnapshot(
        metadata: HistoryMetadata(
          historySnapshotId: 'h1',
          historySchemaVersion: HistoryMetadata.currentSchemaVersion,
          historyCanonicalizationVersion:
              HistoryMetadata.currentCanonicalizationVersion,
          projectId: snapshot.metadata.projectId,
          createdAt: ReleaseSupplyChainTestFixtures.referenceTime,
          snapshotFingerprint: artifact.fingerprint,
          artifactCount: 1,
          artifactTypes: const [HistoryArtifactType.releaseSupplyChain],
          status: HistorySnapshotStatus.complete,
        ),
        artifacts: [artifact],
      );
      final to = HistorySnapshot(
        metadata: from.metadata.copyWith(historySnapshotId: 'h2'),
        artifacts: [mapper.fromMap(snapshot.toJson())],
      );
      final diff = const HistoryComparator().compare(from, to);
      expect(
        diff.changes.where(
          (c) => c.changeType != HistoryChangeType.artifactUnchanged,
        ),
        isEmpty,
      );
    });

    test('dashboard renders supply chain sbom and compliance sections', () {
      final snapshot =
          ReleaseSupplyChainTestFixtures.validSupplyChainSnapshot();
      final registry = DashboardRegistry()
        ..registerBuilder(const SupplyChainSectionBuilder())
        ..registerBuilder(const SbomSectionBuilder())
        ..registerBuilder(const ComplianceSectionBuilder())
        ..freeze();
      final sections = DashboardComposer(registry: registry).compose(
        request: DashboardRequest(
          projectId: snapshot.metadata.projectId,
          createdAt: ReleaseSupplyChainTestFixtures.referenceTime,
          referenceTime: ReleaseSupplyChainTestFixtures.referenceTime,
          releaseSupplyChainSnapshot: snapshot,
          requestedSections: {
            DashboardSectionType.supplyChain,
            DashboardSectionType.sbom,
            DashboardSectionType.compliance,
          },
        ),
        sources: DashboardResolvedSources(releaseSupplyChain: snapshot),
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );
      expect(sections, hasLength(3));
      expect(
        sections
            .every((s) => s.availability == DashboardAvailability.available),
        isTrue,
      );
    });

    test('evaluatePassingSnapshot produces operational snapshot', () async {
      final result = await evaluatePassingSnapshot();
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.fingerprint, isNotEmpty);
    });
  });
}
