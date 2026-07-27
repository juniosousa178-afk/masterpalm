import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/cicd_deployment_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/cicd_execution_section_builder.dart';
import 'package:masterpalm_platform/dashboard/builders/cicd_pipeline_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_composer.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/mappers/cicd_integration_history_mapper.dart';
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
import 'package:masterpalm_platform/report/sources/cicd_integration_report_source.dart';
import 'package:test/test.dart';

import '../release_evidence/support/release_evidence_test_fixtures.dart';
import '../release_governance/support/release_governance_test_fixtures.dart';
import '../release_supply_chain/support/release_supply_chain_test_fixtures.dart';
import 'support/cicd_integration_hardening_helpers.dart';
import 'support/cicd_integration_operational_fixtures.dart';

void main() {
  group('CI/CD Integration integration audits', () {
    Future<dynamic> publishedSnapshot() async {
      final result = await publishPassingSnapshot();
      return result.snapshot!;
    }

    test('report full snapshot generates sections', () async {
      final snapshot = await publishedSnapshot();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.cicdIntegration,
          projectId: snapshot.metadata.projectId,
          cicdIntegrationSnapshot: snapshot.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
      final input = const CicdIntegrationReportSource().fromSnapshot(snapshot);
      expect(input.snapshotId, snapshot.metadata.cicdIntegrationSnapshotId);
      expect(input.fingerprint, snapshot.fingerprint);
    });

    test('report partial snapshot still renders', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final partial = (await core.cicdIntegration().evaluate(
                CicdIntegrationOperationalFixtures.partialRequest(),
              ))
          .snapshot!;
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.cicdIntegration,
          projectId: partial.metadata.projectId,
          cicdIntegrationSnapshot: partial.toJson(),
        ),
      );
      expect(report.document.metadata.reportType, ReportType.cicdIntegration);
    });

    test('history diff is deterministic for same inputs', () async {
      const mapper = CicdIntegrationHistoryMapper();
      final snapshot = await publishedSnapshot();
      final a1 = mapper.fromMap(snapshot.toJson());
      final a2 = mapper.fromMap(snapshot.toJson());
      expect(a1.fingerprint, a2.fingerprint);

      final changes = mapper.compare(snapshot, snapshot);
      expect(changes, isEmpty);
    });

    test('history comparator replays equivalent snapshots', () async {
      const mapper = CicdIntegrationHistoryMapper();
      final snapshot = await publishedSnapshot();
      final artifact = mapper.fromMap(snapshot.toJson());
      final from = HistorySnapshot(
        metadata: HistoryMetadata(
          historySnapshotId: 'h1',
          historySchemaVersion: HistoryMetadata.currentSchemaVersion,
          historyCanonicalizationVersion:
              HistoryMetadata.currentCanonicalizationVersion,
          projectId: snapshot.metadata.projectId,
          createdAt: CicdIntegrationOperationalFixtures.referenceTime,
          snapshotFingerprint: artifact.fingerprint,
          artifactCount: 1,
          artifactTypes: const [HistoryArtifactType.cicdIntegration],
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

    test('dashboard renders cicd pipeline execution deployment sections',
        () async {
      final snapshot = await publishedSnapshot();
      final registry = DashboardRegistry()
        ..registerBuilder(const CicdPipelineSectionBuilder())
        ..registerBuilder(const CicdExecutionSectionBuilder())
        ..registerBuilder(const CicdDeploymentSectionBuilder())
        ..freeze();
      final sections = DashboardComposer(registry: registry).compose(
        request: DashboardRequest(
          projectId: snapshot.metadata.projectId,
          createdAt: CicdIntegrationOperationalFixtures.referenceTime,
          referenceTime: CicdIntegrationOperationalFixtures.referenceTime,
          cicdIntegrationSnapshot: snapshot,
          requestedSections: {
            DashboardSectionType.cicdPipeline,
            DashboardSectionType.cicdExecution,
            DashboardSectionType.cicdDeployment,
          },
        ),
        sources: DashboardResolvedSources(cicdIntegration: snapshot),
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

    test('upstream fingerprints unchanged after cicd evaluation', () async {
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

      final evidenceFpBefore = reResult.bundle!.fingerprint;
      final supplyChainFpBefore = rscResult.snapshot!.fingerprint;

      await core.cicdIntegration().evaluate(
            CicdIntegrationOperationalFixtures.passingRequest(
              releaseEvidenceBundle: reResult.bundle,
              releaseSupplyChainSnapshot: rscResult.snapshot,
            ),
          );

      expect(reResult.bundle!.fingerprint, evidenceFpBefore);
      expect(rscResult.snapshot!.fingerprint, supplyChainFpBefore);
    });
  });
}
