import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/dashboard/builders/release_evidence_section_builder.dart';
import 'package:masterpalm_platform/dashboard/dashboard_composer.dart';
import 'package:masterpalm_platform/dashboard/dashboard_registry.dart';
import 'package:masterpalm_platform/dashboard/dashboard_source_resolver.dart';
import 'package:masterpalm_platform/history/history_comparator.dart';
import 'package:masterpalm_platform/history/mappers/release_evidence_history_mapper.dart';
import 'package:masterpalm_platform/interfaces/release_evidence_provider.dart';
import 'package:masterpalm_platform/interfaces/release_governance_provider.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_enums.dart';
import 'package:masterpalm_platform/models/dashboard/dashboard_request.dart';
import 'package:masterpalm_platform/models/history/history_artifact_type.dart';
import 'package:masterpalm_platform/models/history/history_change_type.dart';
import 'package:masterpalm_platform/models/history/history_metadata.dart';
import 'package:masterpalm_platform/models/history/history_snapshot.dart';
import 'package:masterpalm_platform/models/history/history_snapshot_status.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_bundle.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_enums.dart';
import 'package:masterpalm_platform/models/release_evidence/release_evidence_result.dart';
import 'package:masterpalm_platform/models/observability/telemetry_enums.dart';
import 'package:masterpalm_platform/models/report/report_request.dart';
import 'package:masterpalm_platform/models/report/report_type.dart';
import 'package:masterpalm_platform/report/report_engine.dart';
import 'package:masterpalm_platform/report/sources/release_evidence_report_source.dart';
import 'package:masterpalm_platform/release_evidence/policies/release_evidence_policy_v1.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_bundle_builder.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_collector.dart';
import 'package:masterpalm_platform/release_evidence/release_evidence_source_resolver.dart';
import 'package:masterpalm_platform/release_evidence/resolved_release_evidence_sources.dart';
import 'package:test/test.dart';

import '../release_governance/support/release_governance_test_fixtures.dart';
import 'support/release_evidence_test_fixtures.dart';

void main() {
  group('Release Evidence integration', () {
    late ReleaseEvidenceProvider evidenceProvider;
    late ReleaseGovernanceProvider governanceProvider;

    setUp(() {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      evidenceProvider = core.releaseEvidence();
      governanceProvider = core.releaseGovernance();
    });

    Future<ReleaseEvidenceBundle> evaluatePublishedBundle() async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final result = await evidenceProvider.evaluateAndPublish(
        ReleaseEvidenceTestFixtures.passingRequest(
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
      );
      expect(result.bundle, isNotNull);
      return result.bundle!;
    }

    test('source resolver prefers injected snapshots over byId', () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final resolver = ReleaseEvidenceSourceResolver(
        qualityGateProvider: core.qualityGate(),
        releaseGovernanceProvider: core.releaseGovernance(),
      );
      final qg = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      final request = ReleaseEvidenceTestFixtures.passingRequest(
        qualityGateSnapshot: qg,
      );

      final sources = await resolver.resolveAll(
        request,
        injectedEvidencePolicy: ReleaseEvidencePolicyV1.create(),
      );

      expect(sources.qualityGateSnapshot.isAvailable, isTrue);
      expect(
        sources.qualityGateSnapshot.resolutionMode,
        ReleaseEvidenceSourceResolutionMode.injected,
      );
      expect(sources.resolutionSummary.injectedSources, isNotEmpty);
    });

    test('collector locates artifacts without rebuilding snapshots', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final qg = ReleaseEvidenceTestFixtures.passingQualityGateSnapshot();
      final qgFingerprint = qg.metadata.qualityGateFingerprint;

      final context = ReleaseEvidenceEvaluationContext(
        request: ReleaseEvidenceTestFixtures.passingRequest(
          qualityGateSnapshot: qg,
          releaseDecisionSnapshot: rgResult.snapshot,
        ),
        sources: ResolvedReleaseEvidenceSources(
          releaseContext: ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseContext,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            state: ResolvedReleaseEvidenceSourceState.available,
          ),
          qualityGateSnapshot: ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.qualityGate,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            state: ResolvedReleaseEvidenceSourceState.available,
            resolvedArtifact: qg,
          ),
          releaseDecisionSnapshot: ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseGovernance,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            state: ResolvedReleaseEvidenceSourceState.available,
            resolvedArtifact: rgResult.snapshot,
          ),
          evidencePolicy: ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseContext,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            state: ResolvedReleaseEvidenceSourceState.available,
            resolvedArtifact: ReleaseEvidencePolicyV1.create(),
          ),
          attestationPolicy: const ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseContext,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.notRequested,
            state: ResolvedReleaseEvidenceSourceState.notRequested,
          ),
          verificationPolicy: const ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseContext,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.notRequested,
            state: ResolvedReleaseEvidenceSourceState.notRequested,
          ),
          evidenceReferences: const ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseContext,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.notRequested,
            state: ResolvedReleaseEvidenceSourceState.notRequested,
          ),
          attestationSet: ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.releaseContext,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            state: ResolvedReleaseEvidenceSourceState.available,
            resolvedArtifact: ReleaseEvidenceTestFixtures.validAttestationSet(),
          ),
          provenance: ResolvedReleaseEvidenceSource(
            sourceType: ReleaseEvidenceType.provenance,
            resolutionMode: ReleaseEvidenceSourceResolutionMode.injected,
            state: ResolvedReleaseEvidenceSourceState.available,
            resolvedArtifact: [ReleaseEvidenceTestFixtures.validProvenance()],
          ),
          sourceReferences: const [],
          resolutionSummary: const ReleaseEvidenceSourceResolutionSummary(
            resolvedSources: [],
            unresolvedSources: [],
            injectedSources: [],
          ),
        ),
        evidencePolicy: ReleaseEvidencePolicyV1.create(),
      );

      final collected = const ReleaseEvidenceCollector().collect(context);
      expect(collected.qualityGateSnapshot?.metadata.qualityGateFingerprint,
          qgFingerprint);
      expect(collected.evidence, isNotEmpty);
      expect(collected.attestations, isNotEmpty);
    });

    test('bundle builder produces sorted deterministic bundle', () async {
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final resolver = ReleaseEvidenceSourceResolver(
        qualityGateProvider: core.qualityGate(),
        releaseGovernanceProvider: core.releaseGovernance(),
      );
      final policy = ReleaseEvidencePolicyV1.create();
      final request = ReleaseEvidenceTestFixtures.passingRequest(
        releaseDecisionSnapshot: rgResult.snapshot,
      );
      final sources = await resolver.resolveAll(
        request,
        injectedEvidencePolicy: policy,
      );
      final context = ReleaseEvidenceEvaluationContext(
        request: request,
        sources: sources,
        evidencePolicy: policy,
      );
      final collected = const ReleaseEvidenceCollector().collect(context);
      final bundle = ReleaseEvidenceBundleBuilder().build(
        context: context,
        collected: collected,
        evaluatedAt: ReleaseEvidenceTestFixtures.referenceTime,
      );

      final evidenceIds =
          bundle.evidence.map((e) => e.artifactReference.artifactId).toList();
      expect(evidenceIds, equals(evidenceIds.toList()..sort()));
      expect(bundle.fingerprint, isNotEmpty);
      expect(bundle.coverage.evidenceCoveragePercentage, greaterThan(0));
    });

    test('report consumes bundle without executing engines', () async {
      final bundle = await evaluatePublishedBundle();
      final source = const ReleaseEvidenceReportSource();
      final input = source.fromBundle(bundle);

      final report = await ReportEngine().generate(
        ReportRequest(
          reportType: ReportType.releaseEvidence,
          projectId: bundle.metadata.projectId,
          releaseEvidenceBundle: bundle.toJson(),
        ),
      );

      expect(report.document.metadata.reportType, ReportType.releaseEvidence);
      expect(report.document.sections.isNotEmpty, isTrue);
      expect(input.bundleId, bundle.metadata.bundleId);
      expect(input.fingerprint, bundle.fingerprint);
    });

    test('history mapper produces artifact and comparator diffs coverage',
        () async {
      const mapper = ReleaseEvidenceHistoryMapper();
      final bundle = await evaluatePublishedBundle();
      final artifact = mapper.fromMap(bundle.toJson());

      expect(artifact.artifactType, HistoryArtifactType.releaseEvidence);
      expect(artifact.artifactId, bundle.metadata.bundleId);
      expect(artifact.fingerprint, isNotEmpty);

      final modifiedJson = bundle.toJson();
      modifiedJson['coverage'] = {
        ...bundle.coverage.toJson(),
        'evidenceCoveragePercentage': 50,
      };
      final modifiedBundle = ReleaseEvidenceBundle.fromJson(modifiedJson);
      final changes = mapper.compare(bundle, modifiedBundle);
      expect(changes.any((c) => c.subjectId == 'evidenceCoverage'), isTrue);

      final fromHistory = _historySnapshot('hist-re-from', bundle.toJson());
      final toHistory = _historySnapshot('hist-re-to', modifiedJson);
      final diff = const HistoryComparator().compare(fromHistory, toHistory);
      expect(
        diff.changes.any(
          (c) =>
              c.changeType == HistoryChangeType.artifactChanged ||
              c.subjectId == 'evidenceCoverage',
        ),
        isTrue,
      );
    });

    test('dashboard section builder uses injected bundle only', () async {
      final bundle = await evaluatePublishedBundle();
      final registry = DashboardRegistry();
      registry.registerBuilder(const ReleaseEvidenceSectionBuilder());
      registry.freeze();

      final composer = DashboardComposer(registry: registry);
      final sections = composer.compose(
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

      final section = sections.firstWhere(
        (s) => s.type == DashboardSectionType.releaseEvidence,
      );
      expect(section.availability, DashboardAvailability.available);
      expect(section.widgets, isNotEmpty);
    });

    test(
        'observability component registered and evaluate unchanged when disabled',
        () async {
      final core = PlatformBootstrap.forRepo(Directory.current.path);
      final rgResult = await governanceProvider.evaluate(
        ReleaseGovernanceTestFixtures.passingRequest(),
      );
      final request = ReleaseEvidenceTestFixtures.passingRequest(
        releaseDecisionSnapshot: rgResult.snapshot,
      );
      final first = await core.releaseEvidence().evaluate(request);
      final second = await core.releaseEvidence().evaluate(request);

      expect(first.bundle?.fingerprint, second.bundle?.fingerprint);
      expect(TelemetryComponent.releaseEvidence.wireName, 'releaseEvidence');
    });

    test('end-to-end publish load latest query', () async {
      final bundle = await evaluatePublishedBundle();
      final loaded = await evidenceProvider.load(bundle.metadata.bundleId);
      expect(loaded?.fingerprint, bundle.fingerprint);

      final latest = await evidenceProvider.latest(
        projectId: bundle.metadata.projectId,
        releaseId: bundle.metadata.releaseId,
      );
      expect(latest?.metadata.bundleId, bundle.metadata.bundleId);
    });
  });
}

HistorySnapshot _historySnapshot(String id, Map<String, dynamic> payload) {
  const mapper = ReleaseEvidenceHistoryMapper();
  final artifact = mapper.fromMap(payload);
  return HistorySnapshot(
    metadata: HistoryMetadata(
      historySnapshotId: id,
      historySchemaVersion: HistoryMetadata.currentSchemaVersion,
      historyCanonicalizationVersion:
          HistoryMetadata.currentCanonicalizationVersion,
      projectId: ReleaseEvidenceTestFixtures.projectId,
      createdAt: ReleaseEvidenceTestFixtures.referenceTime,
      snapshotFingerprint: artifact.fingerprint,
      artifactCount: 1,
      artifactTypes: const [HistoryArtifactType.releaseEvidence],
      status: HistorySnapshotStatus.complete,
    ),
    artifacts: [artifact],
  );
}
