import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/release_governance_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_composer.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/mappers/release_governance_history_mapper.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/release_governance/release_decision_snapshot.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_enums.dart';
import 'package:masterpalm_platform/models/release_governance/release_governance_request.dart';
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
import 'package:masterpalm_platform/report/sources/release_governance_report_source.dart';
import 'package:test/test.dart';

import 'support/release_governance_test_fixtures.dart';

void main() {
  group('Release Governance integration', () {
    late ReleaseGovernanceProvider provider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      provider = core.releaseGovernance();
    });

    Future<ReleaseDecisionSnapshot> evaluatePassingSnapshot() async {
      final result = await provider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      expect(result.snapshot, isNotNull);
      return result.snapshot!;
    }

    test('PlatformCore resolves ReleaseGovernanceProvider', () {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      expect(core.releaseGovernance(), isA<ReleaseGovernanceProvider>());
    });

    test('report consumes snapshot without executing engine', () async {
      final snapshot = await evaluatePassingSnapshot();
      final source = const ReleaseGovernanceReportSource();
      final input = source.fromSnapshot(snapshot);

      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseGovernance,
          projectId: snapshot.metadata.projectId,
          releaseDecisionSnapshot: snapshot.toJson(),
        ),
      );

      expect(report.document.metadata.reportType, ReportType.releaseGovernance);
      expect(report.document.sections.isNotEmpty, isTrue);
      expect(input.snapshotId, snapshot.metadata.snapshotId);
      expect(input.decision, snapshot.decision.wireName);
      expect(input.fingerprint, snapshot.fingerprint);
    });

    test('history mapper produces artifact and comparator diffs decision',
        () async {
      const mapper = ReleaseGovernanceHistoryMapper();
      final approved = await evaluatePassingSnapshot();
      final artifact = mapper.fromMap(approved.toJson());

      expect(artifact.artifactType, HistoryArtifactType.releaseGovernance);
      expect(artifact.artifactId, approved.metadata.snapshotId);
      expect(artifact.fingerprint, isNotEmpty);

      final pendingRequest = ReleaseGovernanceRequest(
        releaseContext: ReleaseGovernanceTestFixtures.validContext(),
        policyId: ReleaseGovernanceTestFixtures.policyId,
        qualityGateSnapshot:
            ReleaseGovernanceTestFixtures.passingQualityGateSnapshot(),
        referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
      );
      final pendingResult = await provider.evaluate(pendingRequest);
      final pending = pendingResult.snapshot!;

      final mapperChanges = mapper.compare(approved, pending);
      expect(mapperChanges.any((c) => c.subjectId == 'decision'), isTrue);

      final fromHistory = _historySnapshot('hist-from', approved.toJson());
      final toHistory = _historySnapshot('hist-to', pending.toJson());
      final diff = const HistoryComparator().compare(fromHistory, toHistory);
      expect(
        diff.changes.any((c) => c.subjectId == approved.metadata.snapshotId),
        isTrue,
      );
      expect(
        diff.changes.any(
          (c) =>
              c.changeType == HistoryChangeType.artifactChanged ||
              c.subjectId == 'decision',
        ),
        isTrue,
      );
    });

    test(
        'dashboard section builder via DashboardComposer uses injected snapshot',
        () async {
      final snapshot = await evaluatePassingSnapshot();
      final registry = DashboardRegistry();
      registry.registerBuilder(const ReleaseGovernanceSectionBuilder());
      registry.freeze();

      final composer = DashboardComposer(registry: registry);
      final sections = composer.compose(
        request: DashboardRequest(
          projectId: snapshot.metadata.projectId,
          createdAt: ReleaseGovernanceTestFixtures.referenceTime,
          referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
          releaseDecisionSnapshot: snapshot,
        ),
        sources: DashboardResolvedSources(releaseGovernance: snapshot),
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );

      final rgSection = sections.firstWhere(
        (s) => s.type == DashboardSectionType.releaseGovernance,
      );
      expect(rgSection.availability, DashboardAvailability.available);
      expect(
        rgSection.widgets
            .any((w) => w.widgetId == 'releaseGovernance.decision'),
        isTrue,
      );
    });

    test('dogfooding chain evaluate once then report history dashboard',
        () async {
      final snapshot = await evaluatePassingSnapshot();
      final snapshotJson = snapshot.toJson();

      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseGovernance,
          projectId: snapshot.metadata.projectId,
          releaseDecisionSnapshot: snapshotJson,
        ),
      );
      expect(report.document.sections.isNotEmpty, isTrue);

      const mapper = ReleaseGovernanceHistoryMapper();
      final artifact = mapper.fromMap(snapshotJson);
      expect(artifact.artifactId, snapshot.metadata.snapshotId);

      final registry = DashboardRegistry();
      registry.registerBuilder(const ReleaseGovernanceSectionBuilder());
      registry.freeze();
      final sections = DashboardComposer(registry: registry).compose(
        request: DashboardRequest(
          projectId: snapshot.metadata.projectId,
          createdAt: ReleaseGovernanceTestFixtures.referenceTime,
          referenceTime: ReleaseGovernanceTestFixtures.referenceTime,
          releaseDecisionSnapshot: snapshot,
        ),
        sources: DashboardResolvedSources(releaseGovernance: snapshot),
        compatibility: DashboardCompatibility.compatible,
        freshness: DashboardFreshness.current,
      );
      expect(
          sections.any((s) => s.type == DashboardSectionType.releaseGovernance),
          isTrue);

      final encoded = jsonEncode({
        'report': report.document.toJson(),
        'artifact': artifact.toJson(),
        'dashboard': sections.map((s) => s.sectionId).toList(),
      });
      expect(encoded.contains(snapshot.metadata.snapshotId), isTrue);
      expect(encoded.contains(snapshot.fingerprint), isTrue);
    });
  });
}

HistorySnapshot _historySnapshot(String id, Map<String, dynamic> rgJson) {
  const mapper = ReleaseGovernanceHistoryMapper();
  final artifact = mapper.fromMap(rgJson);
  return HistorySnapshot(
    metadata: HistoryMetadata(
      historySnapshotId: id,
      historySchemaVersion: HistoryMetadata.currentSchemaVersion,
      historyCanonicalizationVersion:
          HistoryMetadata.currentCanonicalizationVersion,
      projectId: ReleaseGovernanceTestFixtures.projectId,
      createdAt: ReleaseGovernanceTestFixtures.referenceTime,
      snapshotFingerprint: artifact.fingerprint,
      artifactCount: 1,
      artifactTypes: const [HistoryArtifactType.releaseGovernance],
      status: HistorySnapshotStatus.complete,
    ),
    artifacts: [artifact],
  );
}
