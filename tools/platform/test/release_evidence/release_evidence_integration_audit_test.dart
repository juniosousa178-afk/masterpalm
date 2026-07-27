import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/release_evidence_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_composer.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/mappers/release_evidence_history_mapper.dart';
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
import 'package:masterpalm_platform/report/sources/release_evidence_report_source.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_canonical_serializer.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_hardening_helpers.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence integration audits', () {
    Future<dynamic> publishedBundle() async {
      final result = await evaluatePassingBundle();
      final published = await PlatformBootstrap.forRepo(Directory.current.path)
          .releaseEvidence()
          .evaluateAndPublish(
            ReleaseEvidenceTestFixtures.passingRequest(
              releaseDecisionSnapshot: (await PlatformBootstrap.forRepo(
                Directory.current.path,
              ).releaseGovernance().evaluate(
                        ReleaseGovernanceTestFixtures.passingRequest(),
                      ))
                  .snapshot,
            ),
          );
      return published.bundle!;
    }

    test('report full bundle generates sections', () async {
      final bundle = await publishedBundle();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseEvidence,
          projectId: bundle.metadata.projectId,
          releaseEvidenceBundle: bundle.toJson(),
        ),
      );
      expect(report.document.sections, isNotEmpty);
      final input = const ReleaseEvidenceReportSource().fromBundle(bundle);
      expect(input.evidenceCount, bundle.metadata.evidenceCount);
    });

    test('report partial bundle still renders', () async {
      final bundle = ReleaseEvidenceTestFixtures.validBundle();
      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseEvidence,
          projectId: bundle.metadata.projectId,
          releaseEvidenceBundle: bundle.toJson(),
        ),
      );
      expect(report.document.metadata.reportType, ReportType.releaseEvidence);
    });

    test('history diff is deterministic for same inputs', () async {
      const mapper = ReleaseEvidenceHistoryMapper();
      final bundle = await publishedBundle();
      final a1 = mapper.fromMap(bundle.toJson());
      final a2 = mapper.fromMap(bundle.toJson());
      expect(a1.fingerprint, a2.fingerprint);

      final modified = bundle.toJson();
      modified['eligibility'] = {
        ...bundle.eligibility.toJson(),
        'status': 'ineligible',
      };
      final changes = mapper.compare(bundle, bundle);
      expect(changes, isEmpty);
      final changes2 = mapper.compare(
        bundle,
        bundle, // same
      );
      expect(changes2, isEmpty);
    });

    test('history comparator replays equivalent snapshots', () async {
      const mapper = ReleaseEvidenceHistoryMapper();
      final bundle = await publishedBundle();
      final artifact = mapper.fromMap(bundle.toJson());
      final from = HistorySnapshot(
        metadata: HistoryMetadata(
          historySnapshotId: 'h1',
          historySchemaVersion: HistoryMetadata.currentSchemaVersion,
          historyCanonicalizationVersion:
              HistoryMetadata.currentCanonicalizationVersion,
          projectId: bundle.metadata.projectId,
          createdAt: ReleaseEvidenceTestFixtures.referenceTime,
          snapshotFingerprint: artifact.fingerprint,
          artifactCount: 1,
          artifactTypes: const [HistoryArtifactType.releaseEvidence],
          status: HistorySnapshotStatus.complete,
        ),
        artifacts: [artifact],
      );
      final to = HistorySnapshot(
        metadata: from.metadata.copyWith(historySnapshotId: 'h2'),
        artifacts: [mapper.fromMap(bundle.toJson())],
      );
      final diff = const HistoryComparator().compare(from, to);
      expect(
        diff.changes.where(
          (c) => c.changeType != HistoryChangeType.artifactUnchanged,
        ),
        isEmpty,
      );
    });

    test('dashboard renders bundle coverage and warnings', () async {
      final bundle = await publishedBundle();
      final registry = DashboardRegistry()
        ..registerBuilder(const ReleaseEvidenceSectionBuilder())
        ..freeze();
      final sections = DashboardComposer(registry: registry).compose(
        request: DashboardRequest(
          projectId: bundle.metadata.projectId,
          createdAt: ReleaseEvidenceTestFixtures.referenceTime,
          referenceTime: ReleaseEvidenceTestFixtures.referenceTime,
          releaseEvidenceBundle: bundle,
          requestedSections: {DashboardSectionType.releaseEvidence},
        ),
        sources: DashboardResolvedSources(releaseEvidence: bundle),
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );
      final section = sections.first;
      expect(
          section.widgets.any((w) => w.widgetId.contains('coverage')), isTrue);
    });
  });
}
