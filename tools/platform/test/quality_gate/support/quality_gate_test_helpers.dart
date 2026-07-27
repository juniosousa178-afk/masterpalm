import 'dart:io';

import 'package:masterpalm_platform/core/platform_bootstrap.dart';
import 'package:masterpalm_platform/mes/policies/mes_official_policy_v1.dart';
import 'package:masterpalm_platform/models/analysis_result.dart';
import 'package:masterpalm_platform/models/history/history_change_type.dart';
import 'package:masterpalm_platform/models/history/history_compatibility.dart';
import 'package:masterpalm_platform/models/history/history_diff.dart';
import 'package:masterpalm_platform/models/mes/mes_request.dart';
import 'package:masterpalm_platform/models/mes/mes_snapshot.dart';
import 'package:masterpalm_platform/models/metrics/metrics_snapshot.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_enums.dart';
import 'package:masterpalm_platform/models/quality_gate/quality_gate_request.dart';
import 'package:masterpalm_platform/models/score/score_request.dart';
import 'package:masterpalm_platform/models/score/score_snapshot.dart';
import 'package:masterpalm_platform/quality_gate/policies/quality_gate_release_policy_v1.dart';
import 'package:masterpalm_platform/quality_gate/resolved_quality_gate_sources.dart';
import 'package:masterpalm_platform/score/policies/foundation_reference_policy.dart';

import '../../score/score_fixtures.dart';

/// Shared builders for Quality Gate tests.
class QualityGateTestHelpers {
  static const createdAt = '2026-01-01T10:00:00.000Z';
  static const referenceTime = '2026-01-01T10:00:01.000Z';
  static const commitId = 'abc123';

  static AnalysisResult guardianGo() => AnalysisResult(
        success: true,
        summary: 'GO',
        details: ScoreFixtures.guardianGo(),
      );

  static Future<MetricsSnapshot> minimalMetrics({
    String projectId = ScoreFixtures.projectId,
    String? gitRef,
  }) async {
    final snapshot = await ScoreFixtures.metricsComplete(
      guardianAnalysis: guardianGo().details,
    );
    if (gitRef == null) return snapshot;
    final json = snapshot.toJson();
    final meta = Map<String, dynamic>.from(
      json['metadata'] as Map<String, dynamic>,
    );
    meta['gitRef'] = gitRef;
    json['metadata'] = meta;
    return MetricsSnapshot.fromJson(json);
  }

  static Future<EngineeringScoreSnapshot> minimalScore({
    String projectId = ScoreFixtures.projectId,
    String? gitRef,
    double score = 82,
    double coverage = 90,
  }) async {
    final core = PlatformBootstrap.forRepo(Directory.current.path);
    final metrics = await minimalMetrics(projectId: projectId);
    final result = await core.score().calculate(
          ScoreRequest(
            projectId: projectId,
            createdAt: '2026-01-01T10:00:00.000Z',
            metricsSnapshot: metrics.toJson(),
            guardianAnalysis: guardianGo().details,
            policyId: FoundationReferencePolicy.policyId,
          ),
        );
    final json = result.snapshot.toJson();
    final overall = Map<String, dynamic>.from(
      json['overallScore'] as Map<String, dynamic>,
    );
    overall['value'] = score;
    json['overallScore'] = overall;
    final cov = Map<String, dynamic>.from(
      json['coverage'] as Map<String, dynamic>,
    );
    cov['coveragePercentage'] = coverage;
    json['coverage'] = cov;
    if (gitRef != null) {
      final meta = Map<String, dynamic>.from(
        json['metadata'] as Map<String, dynamic>,
      );
      meta['gitRef'] = gitRef;
      meta['compatibilityStatus'] = 'compatible';
      json['metadata'] = meta;
    }
    return EngineeringScoreSnapshot.fromJson(json);
  }

  static Future<MESSnapshot> minimalMes({
    String projectId = ScoreFixtures.projectId,
    String? gitRef,
    double score = 84,
    double coverage = 92,
  }) async {
    final core = PlatformBootstrap.forRepo(Directory.current.path);
    final metrics = await minimalMetrics(projectId: projectId);
    final result = await core.mes().calculate(
          MESRequest(
            projectId: projectId,
            createdAt: '2026-01-01T10:00:00.000Z',
            metricsSnapshot: metrics.toJson(),
            guardianAnalysis: guardianGo().details,
            policyId: MesOfficialPolicyV1.policyId,
          ),
        );
    final json = result.snapshot!.toJson();
    final mesValue = Map<String, dynamic>.from(
      json['mesValue'] as Map<String, dynamic>,
    );
    mesValue['value'] = score;
    json['mesValue'] = mesValue;
    final cov = Map<String, dynamic>.from(
      json['coverage'] as Map<String, dynamic>,
    );
    cov['dimensionCoverage'] = coverage;
    json['coverage'] = cov;
    final elig = Map<String, dynamic>.from(
      json['eligibility'] as Map<String, dynamic>,
    );
    elig['status'] = 'eligible';
    json['eligibility'] = elig;
    if (gitRef != null) {
      final meta = Map<String, dynamic>.from(
        json['metadata'] as Map<String, dynamic>,
      );
      meta['gitRef'] = gitRef;
      meta['compatibilityStatus'] = 'compatible';
      json['metadata'] = meta;
    }
    return MESSnapshot.fromJson(json);
  }

  static AnalysisResult guardianNoGo() => AnalysisResult(
        success: false,
        summary: 'NO-GO',
        details: ScoreFixtures.guardianNoGo(),
      );

  static Future<QualityGateRequest> passingRequest({
    AnalysisResult? guardian,
    String projectId = ScoreFixtures.projectId,
  }) async {
    final core = PlatformBootstrap.forRepo(Directory.current.path);
    final metrics = await ScoreFixtures.metricsComplete(
      guardianAnalysis: (guardian ?? guardianGo()).details,
    );
    final scoreResult = await core.score().calculate(
          ScoreRequest(
            projectId: projectId,
            createdAt: createdAt,
            metricsSnapshot: metrics.toJson(),
            guardianAnalysis: (guardian ?? guardianGo()).details,
            policyId: FoundationReferencePolicy.policyId,
          ),
        );
    final mesResult = await core.mes().calculate(
          MESRequest(
            projectId: projectId,
            createdAt: createdAt,
            metricsSnapshot: metrics.toJson(),
            guardianAnalysis: (guardian ?? guardianGo()).details,
            policyId: MesOfficialPolicyV1.policyId,
          ),
        );

    final metricsJson = metrics.toJson();
    final metricsMeta = Map<String, dynamic>.from(
      metricsJson['metadata'] as Map<String, dynamic>,
    );
    metricsMeta['gitRef'] = commitId;
    metricsJson['metadata'] = metricsMeta;
    final patchedMetrics = MetricsSnapshot.fromJson(metricsJson);

    final scoreJson = scoreResult.snapshot.toJson();
    final overallScore = Map<String, dynamic>.from(
      scoreJson['overallScore'] as Map<String, dynamic>,
    );
    overallScore['value'] = 82;
    scoreJson['overallScore'] = overallScore;
    final scoreCoverage = Map<String, dynamic>.from(
      scoreJson['coverage'] as Map<String, dynamic>,
    );
    scoreCoverage['coveragePercentage'] = 90;
    scoreJson['coverage'] = scoreCoverage;
    final scoreMeta = Map<String, dynamic>.from(
      scoreJson['metadata'] as Map<String, dynamic>,
    );
    scoreMeta['gitRef'] = commitId;
    scoreMeta['compatibilityStatus'] = 'compatible';
    scoreJson['metadata'] = scoreMeta;

    final mesJson = mesResult.snapshot!.toJson();
    final mesValue = Map<String, dynamic>.from(
      mesJson['mesValue'] as Map<String, dynamic>,
    );
    mesValue['value'] = 84;
    mesJson['mesValue'] = mesValue;
    final mesCoverage = Map<String, dynamic>.from(
      mesJson['coverage'] as Map<String, dynamic>,
    );
    mesCoverage['dimensionCoverage'] = 92;
    mesJson['coverage'] = mesCoverage;
    final mesEligibility = Map<String, dynamic>.from(
      mesJson['eligibility'] as Map<String, dynamic>,
    );
    mesEligibility['status'] = 'eligible';
    mesJson['eligibility'] = mesEligibility;
    final mesMeta = Map<String, dynamic>.from(
      mesJson['metadata'] as Map<String, dynamic>,
    );
    mesMeta['gitRef'] = commitId;
    mesMeta['compatibilityStatus'] = 'compatible';
    mesJson['metadata'] = mesMeta;

    return QualityGateRequest(
      projectId: projectId,
      policyId: QualityGateReleasePolicyV1.policyId,
      commitId: commitId,
      createdAt: createdAt,
      referenceTime: referenceTime,
      metricsSnapshot: patchedMetrics,
      guardianAnalysis: guardian ?? guardianGo(),
      engineeringScoreSnapshot: EngineeringScoreSnapshot.fromJson(scoreJson),
      mesSnapshot: MESSnapshot.fromJson(mesJson),
    );
  }

  static HistoryDiff minimalHistoryDiff({int regressionCount = 0}) {
    final changes = List.generate(regressionCount, (i) {
      return HistoryChange(
        changeType: HistoryChangeType.metricValueChanged,
        category: HistoryChangeCategory.metrics,
        subjectId: 'metric-$i',
        metadata: const {'regression': 'true'},
      );
    });

    return HistoryDiff(
      fromSnapshotId: 'hist-from',
      toSnapshotId: 'hist-to',
      compatibility: const HistoryCompatibility(
        status: HistoryCompatibilityStatus.compatible,
        reasons: [],
      ),
      changes: changes,
      summary: HistoryDiffSummary(
        totalChanges: changes.length,
        addedCount: 0,
        removedCount: 0,
        changedCount: changes.length,
        unchangedCount: 0,
      ),
    );
  }

  static ResolvedQualityGateSources minimalSources({
    required MetricsSnapshot metrics,
    required EngineeringScoreSnapshot score,
    required MESSnapshot mes,
    HistoryDiff? history,
  }) {
    return ResolvedQualityGateSources(
      metrics: _wrap(
        QualityGateSourceType.metrics,
        metrics,
        metrics.metadata.snapshotId,
        metrics.metadata.projectId,
        metrics.metadata.sourceGraphFingerprint,
      ),
      guardian: ResolvedQualityGateSource<Map<String, dynamic>>(
        sourceType: QualityGateSourceType.guardian,
        resolutionMode: QualityGateSourceResolutionMode.injected,
        state: ResolvedQualityGateSourceState.available,
        resolvedArtifact: guardianGo().details,
        resolvedId: 'guardian:injected',
        projectId: metrics.metadata.projectId,
      ),
      score: _wrap(
        QualityGateSourceType.score,
        score,
        score.metadata.scoreSnapshotId,
        score.metadata.projectId,
        score.metadata.scoreFingerprint,
        policyId: score.metadata.policyId,
        policyVersion: score.metadata.policyVersion,
        gitRef: score.metadata.gitRef,
      ),
      mes: _wrap(
        QualityGateSourceType.mes,
        mes,
        mes.metadata.mesSnapshotId,
        mes.metadata.projectId,
        mes.metadata.mesFingerprint,
        policyId: mes.metadata.policyId,
        policyVersion: mes.metadata.policyVersion,
        gitRef: mes.metadata.gitRef,
      ),
      history: history == null
          ? const ResolvedQualityGateSource<HistoryDiff>(
              sourceType: QualityGateSourceType.history,
              resolutionMode: QualityGateSourceResolutionMode.unavailable,
              state: ResolvedQualityGateSourceState.notRequested,
            )
          : ResolvedQualityGateSource<HistoryDiff>(
              sourceType: QualityGateSourceType.history,
              resolutionMode: QualityGateSourceResolutionMode.injected,
              state: ResolvedQualityGateSourceState.available,
              resolvedArtifact: history,
              resolvedId: '${history.fromSnapshotId}:${history.toSnapshotId}',
              projectId: metrics.metadata.projectId,
            ),
      telemetry: const ResolvedQualityGateSource(
        sourceType: QualityGateSourceType.telemetry,
        resolutionMode: QualityGateSourceResolutionMode.unavailable,
        state: ResolvedQualityGateSourceState.notRequested,
      ),
      dashboard: const ResolvedQualityGateSource(
        sourceType: QualityGateSourceType.dashboard,
        resolutionMode: QualityGateSourceResolutionMode.unavailable,
        state: ResolvedQualityGateSourceState.notRequested,
      ),
      sourceReferences: const [],
      resolutionSummary: const QualityGateSourceResolutionSummary(
        resolvedSources: [],
        missingSources: [],
        incompatibleSources: [],
        requestedSourceCount: 7,
        injectedSourceCount: 4,
        loadedByIdCount: 0,
        loadedLatestCount: 0,
        unavailableSourceCount: 0,
        failedSourceCount: 0,
        availableSourceTypes: [],
        unavailableSourceTypes: [],
        resolutionModesBySource: {},
        warnings: [],
        limitations: [],
        fingerprint: 'test-fp',
      ),
    );
  }

  static ResolvedQualityGateSource<T> _wrap<T>(
    QualityGateSourceType type,
    T artifact,
    String id,
    String projectId,
    String fingerprint, {
    String? policyId,
    int? policyVersion,
    String? gitRef,
  }) {
    return ResolvedQualityGateSource<T>(
      sourceType: type,
      resolutionMode: QualityGateSourceResolutionMode.injected,
      state: ResolvedQualityGateSourceState.available,
      resolvedArtifact: artifact,
      resolvedId: id,
      projectId: projectId,
      fingerprint: fingerprint,
      policyId: policyId,
      policyVersion: policyVersion,
      commitId: gitRef,
    );
  }
}
