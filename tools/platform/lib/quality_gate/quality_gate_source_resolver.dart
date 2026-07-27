import '../interfaces/dashboard_provider.dart';
import '../interfaces/mes_provider.dart';
import '../interfaces/metrics_provider.dart';
import '../interfaces/observability_provider.dart';
import '../interfaces/score_provider.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import '../models/history/history_diff.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/mes/mes_enums.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/observability/telemetry_snapshot.dart';
import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_request.dart';
import '../models/score/score_snapshot.dart';
import 'quality_gate_canonical_serializer.dart';
import 'resolved_quality_gate_sources.dart';

/// Resolves quality gate source artifacts without executing origin engines.
class QualityGateSourceResolver {
  QualityGateSourceResolver({
    required MetricsProvider metricsProvider,
    required ScoreProvider scoreProvider,
    required MESProvider mesProvider,
    required ObservabilityProvider observabilityProvider,
    required DashboardProvider dashboardProvider,
    QualityGateCanonicalSerializer? serializer,
  })  : _metricsProvider = metricsProvider,
        _scoreProvider = scoreProvider,
        _mesProvider = mesProvider,
        _observabilityProvider = observabilityProvider,
        _dashboardProvider = dashboardProvider,
        _serializer = serializer ?? const QualityGateCanonicalSerializer();

  final MetricsProvider _metricsProvider;
  final ScoreProvider _scoreProvider;
  final MESProvider _mesProvider;
  final ObservabilityProvider _observabilityProvider;
  final DashboardProvider _dashboardProvider;
  final QualityGateCanonicalSerializer _serializer;

  Future<ResolvedQualityGateSources> resolveAll(
    QualityGateRequest request,
  ) async {
    final refs = <QualityGateSourceReference>[];
    final warnings = <QualityGateWarning>[];
    final errors = <QualityGateError>[];
    final limitations = <QualityGateLimitation>[];
    final hints = <String>[];

    var injected = 0;
    var byId = 0;
    var latest = 0;
    var unavailable = 0;
    var failed = 0;

    final metrics = await resolveMetrics(request, refs, warnings, limitations);
    _countResolution(metrics,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    final guardian = resolveGuardian(request, refs, limitations);
    _countResolution(guardian,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    final score = await resolveScore(request, refs, warnings, limitations);
    _countResolution(score,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    final mes = await resolveMes(request, refs, warnings, limitations);
    _countResolution(mes,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    final history = resolveHistory(request, refs, limitations);
    _countResolution(history,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    final telemetry =
        await resolveTelemetry(request, refs, warnings, limitations);
    _countResolution(telemetry,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    final dashboard =
        await resolveDashboard(request, refs, warnings, limitations);
    _countResolution(dashboard,
        injected: () => injected++,
        byId: () => byId++,
        latest: () => latest++,
        unavailable: () => unavailable++);

    _checkProjectMismatch(request, metrics, score, mes, hints, limitations);

    refs.sort((a, b) => a.sourceType.wireName.compareTo(b.sourceType.wireName));

    final resolvedTypes = refs
        .where((r) => r.availability == QualityGateSourceAvailability.available)
        .map((r) => r.sourceType)
        .toList();
    final missingTypes = <QualityGateSourceType>[];
    final incompatibleTypes = refs
        .where(
          (r) => r.compatibility == QualityGateCompatibilityStatus.incompatible,
        )
        .map((r) => r.sourceType)
        .toList();

    final summary = QualityGateSourceResolutionSummary(
      resolvedSources: resolvedTypes,
      missingSources: missingTypes,
      incompatibleSources: incompatibleTypes,
      requestedSourceCount: 7,
      injectedSourceCount: injected,
      loadedByIdCount: byId,
      loadedLatestCount: latest,
      unavailableSourceCount: unavailable,
      failedSourceCount: failed,
      availableSourceTypes: resolvedTypes,
      unavailableSourceTypes: missingTypes,
      resolutionModesBySource: {
        for (final r in refs) r.sourceType.wireName: r.resolutionMode.wireName,
      },
      warnings: warnings.map((w) => w.message).toList(),
      limitations: limitations.map((l) => l.description).toList(),
      fingerprint: _serializer.fingerprintFromString(
        refs.map((r) => r.toJson().toString()).join('|'),
      ),
    );

    return ResolvedQualityGateSources(
      metrics: metrics,
      guardian: guardian,
      score: score,
      mes: mes,
      history: history,
      telemetry: telemetry,
      dashboard: dashboard,
      sourceReferences: refs,
      resolutionSummary: summary,
      warnings: warnings,
      errors: errors,
      limitations: limitations,
      compatibilityHints: hints,
    );
  }

  Future<ResolvedQualityGateSource<MetricsSnapshot>> resolveMetrics(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateWarning> warnings,
    List<QualityGateLimitation> limitations,
  ) async {
    if (request.metricsSnapshot != null) {
      final s = request.metricsSnapshot!;
      refs.add(_metricsRef(s, QualityGateSourceResolutionMode.injected));
      return _available(QualityGateSourceType.metrics, s, refs.last);
    }
    if (request.metricsSnapshotId != null) {
      final loaded = await _metricsProvider.load();
      if (loaded != null &&
          loaded.metadata.snapshotId == request.metricsSnapshotId) {
        refs.add(_metricsRef(loaded, QualityGateSourceResolutionMode.byId));
        return _available(QualityGateSourceType.metrics, loaded, refs.last);
      }
      refs.add(_unavailableRef(
        QualityGateSourceType.metrics,
        request.metricsSnapshotId!,
        QualityGateSourceResolutionMode.byId,
      ));
      limitations.add(QualityGateLimitation(
        limitationId: 'missing-metrics',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.blocking,
        sourceType: QualityGateSourceType.metrics,
        description:
            'Metrics snapshot ${request.metricsSnapshotId} unavailable',
        impact: 'Metrics rules cannot be evaluated',
        resolvable: true,
      ));
      return _unavailable(
          QualityGateSourceType.metrics, request.metricsSnapshotId);
    }
    if (request.useLatest) {
      final loaded = await _metricsProvider.load();
      if (loaded != null) {
        refs.add(_metricsRef(loaded, QualityGateSourceResolutionMode.latest));
        return _available(QualityGateSourceType.metrics, loaded, refs.last);
      }
      limitations.add(const QualityGateLimitation(
        limitationId: 'latest-metrics-missing',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.warning,
        sourceType: QualityGateSourceType.metrics,
        description: 'Latest metrics snapshot unavailable',
        impact: 'Metrics rules may be unavailable',
        resolvable: true,
      ));
      return _notRequested(QualityGateSourceType.metrics);
    }
    return _notRequested(QualityGateSourceType.metrics);
  }

  ResolvedQualityGateSource<Map<String, dynamic>> resolveGuardian(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateLimitation> limitations,
  ) {
    final map = guardianAnalysisMap(request.guardianAnalysis);
    if (map != null && map.isNotEmpty) {
      refs.add(QualityGateSourceReference(
        sourceType: QualityGateSourceType.guardian,
        resolutionMode: QualityGateSourceResolutionMode.injected,
        resolvedId: 'guardian:injected',
        fingerprint: _serializer.fingerprintFromString(map.toString()),
        projectId: request.projectId,
        availability: QualityGateSourceAvailability.available,
        compatibility: QualityGateCompatibilityStatus.compatible,
      ));
      return ResolvedQualityGateSource<Map<String, dynamic>>(
        sourceType: QualityGateSourceType.guardian,
        resolutionMode: QualityGateSourceResolutionMode.injected,
        state: ResolvedQualityGateSourceState.available,
        resolvedArtifact: map,
        resolvedId: 'guardian:injected',
        fingerprint: refs.last.fingerprint,
        projectId: request.projectId,
      );
    }
    if (request.guardianAnalysisId != null) {
      refs.add(_unavailableRef(
        QualityGateSourceType.guardian,
        request.guardianAnalysisId!,
        QualityGateSourceResolutionMode.byId,
      ));
      limitations.add(QualityGateLimitation(
        limitationId: 'guardian-byid-unavailable',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.critical,
        sourceType: QualityGateSourceType.guardian,
        description:
            'Guardian analysis ${request.guardianAnalysisId} must be injected',
        impact: 'Guardian rules cannot be evaluated',
        resolvable: true,
        remediationHint: 'Inject guardianAnalysis in the request',
      ));
      return _unavailable(
          QualityGateSourceType.guardian, request.guardianAnalysisId);
    }
    return _notRequested(QualityGateSourceType.guardian);
  }

  Future<ResolvedQualityGateSource<EngineeringScoreSnapshot>> resolveScore(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateWarning> warnings,
    List<QualityGateLimitation> limitations,
  ) async {
    if (request.engineeringScoreSnapshot != null) {
      final s = request.engineeringScoreSnapshot!;
      refs.add(_scoreRef(s, QualityGateSourceResolutionMode.injected));
      return _available(QualityGateSourceType.score, s, refs.last);
    }
    if (request.scoreSnapshotId != null) {
      final loaded =
          await _scoreProvider.load(snapshotId: request.scoreSnapshotId!);
      if (loaded != null) {
        refs.add(_scoreRef(loaded, QualityGateSourceResolutionMode.byId));
        return _available(QualityGateSourceType.score, loaded, refs.last);
      }
      refs.add(_unavailableRef(
        QualityGateSourceType.score,
        request.scoreSnapshotId!,
        QualityGateSourceResolutionMode.byId,
      ));
      limitations.add(QualityGateLimitation(
        limitationId: 'missing-score',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.blocking,
        sourceType: QualityGateSourceType.score,
        description: 'Score snapshot ${request.scoreSnapshotId} unavailable',
        impact: 'Score rules cannot be evaluated',
        resolvable: true,
      ));
      return _unavailable(QualityGateSourceType.score, request.scoreSnapshotId);
    }
    if (request.useLatest) {
      final loaded = await _scoreProvider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(_scoreRef(loaded, QualityGateSourceResolutionMode.latest));
        return _available(QualityGateSourceType.score, loaded, refs.last);
      }
      limitations.add(const QualityGateLimitation(
        limitationId: 'latest-score-missing',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.warning,
        sourceType: QualityGateSourceType.score,
        description: 'Latest score snapshot unavailable',
        impact: 'Score rules may be unavailable',
        resolvable: true,
      ));
    }
    return _notRequested(QualityGateSourceType.score);
  }

  Future<ResolvedQualityGateSource<MESSnapshot>> resolveMes(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateWarning> warnings,
    List<QualityGateLimitation> limitations,
  ) async {
    if (request.mesSnapshot != null) {
      final s = request.mesSnapshot!;
      refs.add(_mesRef(s, QualityGateSourceResolutionMode.injected));
      return _available(QualityGateSourceType.mes, s, refs.last);
    }
    if (request.mesSnapshotId != null) {
      final loaded = await _mesProvider.load(request.mesSnapshotId!);
      if (loaded != null) {
        refs.add(_mesRef(loaded, QualityGateSourceResolutionMode.byId));
        return _available(QualityGateSourceType.mes, loaded, refs.last);
      }
      refs.add(_unavailableRef(
        QualityGateSourceType.mes,
        request.mesSnapshotId!,
        QualityGateSourceResolutionMode.byId,
      ));
      limitations.add(QualityGateLimitation(
        limitationId: 'missing-mes',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.blocking,
        sourceType: QualityGateSourceType.mes,
        description: 'MES snapshot ${request.mesSnapshotId} unavailable',
        impact: 'MES rules cannot be evaluated',
        resolvable: true,
      ));
      return _unavailable(QualityGateSourceType.mes, request.mesSnapshotId);
    }
    if (request.useLatest) {
      final loaded = await _mesProvider.latest(projectId: request.projectId);
      if (loaded != null) {
        refs.add(_mesRef(loaded, QualityGateSourceResolutionMode.latest));
        return _available(QualityGateSourceType.mes, loaded, refs.last);
      }
      limitations.add(const QualityGateLimitation(
        limitationId: 'latest-mes-missing',
        type: QualityGateLimitationType.missingSource,
        severity: QualityGateRuleSeverity.warning,
        sourceType: QualityGateSourceType.mes,
        description: 'Latest MES snapshot unavailable',
        impact: 'MES rules may be unavailable',
        resolvable: true,
      ));
    }
    return _notRequested(QualityGateSourceType.mes);
  }

  ResolvedQualityGateSource<HistoryDiff> resolveHistory(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateLimitation> limitations,
  ) {
    if (request.historyDiff != null) {
      final diff = request.historyDiff!;
      final id = '${diff.fromSnapshotId}:${diff.toSnapshotId}';
      refs.add(QualityGateSourceReference(
        sourceType: QualityGateSourceType.history,
        resolutionMode: QualityGateSourceResolutionMode.injected,
        resolvedId: id,
        fingerprint: id,
        projectId: request.projectId,
        availability: QualityGateSourceAvailability.available,
        compatibility: QualityGateCompatibilityStatus.compatible,
      ));
      return ResolvedQualityGateSource<HistoryDiff>(
        sourceType: QualityGateSourceType.history,
        resolutionMode: QualityGateSourceResolutionMode.injected,
        state: ResolvedQualityGateSourceState.available,
        resolvedArtifact: diff,
        resolvedId: id,
        fingerprint: id,
        projectId: request.projectId,
      );
    }
    if (request.historyDiffId != null) {
      refs.add(_unavailableRef(
        QualityGateSourceType.history,
        request.historyDiffId!,
        QualityGateSourceResolutionMode.byId,
      ));
      limitations.add(const QualityGateLimitation(
        limitationId: 'history-byid-unsupported',
        type: QualityGateLimitationType.providerCapabilityGap,
        severity: QualityGateRuleSeverity.warning,
        sourceType: QualityGateSourceType.history,
        description:
            'HistoryDiff must be injected; load by ID is not supported',
        impact: 'History rules remain optional',
        resolvable: true,
      ));
      return _unavailable(QualityGateSourceType.history, request.historyDiffId);
    }
    return _notRequested(QualityGateSourceType.history);
  }

  Future<ResolvedQualityGateSource<TelemetrySnapshot>> resolveTelemetry(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateWarning> warnings,
    List<QualityGateLimitation> limitations,
  ) async {
    if (request.telemetrySnapshot != null) {
      final s = request.telemetrySnapshot!;
      refs.add(_telemetryRef(s, QualityGateSourceResolutionMode.injected));
      return _available(QualityGateSourceType.telemetry, s, refs.last);
    }
    if (request.telemetrySnapshotId != null) {
      final loaded =
          await _observabilityProvider.load(request.telemetrySnapshotId!);
      if (loaded != null) {
        refs.add(_telemetryRef(loaded, QualityGateSourceResolutionMode.byId));
        return _available(QualityGateSourceType.telemetry, loaded, refs.last);
      }
      refs.add(_unavailableRef(
        QualityGateSourceType.telemetry,
        request.telemetrySnapshotId!,
        QualityGateSourceResolutionMode.byId,
      ));
      return _unavailable(
        QualityGateSourceType.telemetry,
        request.telemetrySnapshotId,
      );
    }
    if (request.useLatest) {
      final loaded = await _observabilityProvider.latest(
        projectId: request.projectId,
      );
      if (loaded != null) {
        refs.add(_telemetryRef(loaded, QualityGateSourceResolutionMode.latest));
        return _available(QualityGateSourceType.telemetry, loaded, refs.last);
      }
    }
    return _notRequested(QualityGateSourceType.telemetry);
  }

  Future<ResolvedQualityGateSource<DashboardSnapshot>> resolveDashboard(
    QualityGateRequest request,
    List<QualityGateSourceReference> refs,
    List<QualityGateWarning> warnings,
    List<QualityGateLimitation> limitations,
  ) async {
    if (request.dashboardSnapshot != null) {
      final s = request.dashboardSnapshot!;
      refs.add(_dashboardRef(s, QualityGateSourceResolutionMode.injected));
      return _available(QualityGateSourceType.dashboard, s, refs.last);
    }
    if (request.dashboardSnapshotId != null) {
      final loaded =
          await _dashboardProvider.load(request.dashboardSnapshotId!);
      if (loaded != null) {
        refs.add(_dashboardRef(loaded, QualityGateSourceResolutionMode.byId));
        return _available(QualityGateSourceType.dashboard, loaded, refs.last);
      }
      refs.add(_unavailableRef(
        QualityGateSourceType.dashboard,
        request.dashboardSnapshotId!,
        QualityGateSourceResolutionMode.byId,
      ));
      return _unavailable(
        QualityGateSourceType.dashboard,
        request.dashboardSnapshotId,
      );
    }
    if (request.useLatest) {
      final loaded = await _dashboardProvider.latest(
        projectId: request.projectId,
        branch: request.branch,
      );
      if (loaded != null) {
        refs.add(_dashboardRef(loaded, QualityGateSourceResolutionMode.latest));
        return _available(QualityGateSourceType.dashboard, loaded, refs.last);
      }
    }
    return _notRequested(QualityGateSourceType.dashboard);
  }

  void _checkProjectMismatch(
    QualityGateRequest request,
    ResolvedQualityGateSource<MetricsSnapshot> metrics,
    ResolvedQualityGateSource<EngineeringScoreSnapshot> score,
    ResolvedQualityGateSource<MESSnapshot> mes,
    List<String> hints,
    List<QualityGateLimitation> limitations,
  ) {
    final expected = request.projectId;
    for (final entry in [
      (
        metrics.resolvedArtifact?.metadata.projectId,
        QualityGateSourceType.metrics
      ),
      (score.resolvedArtifact?.metadata.projectId, QualityGateSourceType.score),
      (mes.resolvedArtifact?.metadata.projectId, QualityGateSourceType.mes),
    ]) {
      final projectId = entry.$1;
      if (projectId != null && projectId != expected) {
        hints.add(
            'Project mismatch on ${entry.$2.wireName}: $projectId != $expected');
        limitations.add(QualityGateLimitation(
          limitationId: 'project-mismatch-${entry.$2.wireName}',
          type: QualityGateLimitationType.incompatibleSource,
          severity: QualityGateRuleSeverity.critical,
          sourceType: entry.$2,
          description:
              'Source ${entry.$2.wireName} projectId $projectId differs from request $expected',
          impact: 'Cross-artifact consistency rules may fail',
          resolvable: false,
        ));
      }
    }
  }

  void _countResolution<T>(
    ResolvedQualityGateSource<T> source, {
    required void Function() injected,
    required void Function() byId,
    required void Function() latest,
    required void Function() unavailable,
  }) {
    switch (source.resolutionMode) {
      case QualityGateSourceResolutionMode.injected:
        if (source.isAvailable) injected();
      case QualityGateSourceResolutionMode.byId:
        if (source.isAvailable) {
          byId();
        } else {
          unavailable();
        }
      case QualityGateSourceResolutionMode.latest:
        if (source.isAvailable) latest();
      case QualityGateSourceResolutionMode.unavailable:
      case QualityGateSourceResolutionMode.incompatible:
        unavailable();
    }
  }

  ResolvedQualityGateSource<T> _available<T>(
    QualityGateSourceType type,
    T artifact,
    QualityGateSourceReference ref,
  ) {
    return ResolvedQualityGateSource<T>(
      sourceType: type,
      resolutionMode: ref.resolutionMode,
      state: ResolvedQualityGateSourceState.available,
      resolvedArtifact: artifact,
      resolvedId: ref.resolvedId,
      fingerprint: ref.fingerprint,
      projectId: ref.projectId,
      commitId: ref.commitId,
      branch: ref.branch,
      policyId: ref.policyId,
      policyVersion: ref.policyVersion,
      schemaVersion: ref.schemaVersion,
      calculationVersion: ref.calculationVersion,
    );
  }

  ResolvedQualityGateSource<T> _unavailable<T>(
    QualityGateSourceType type,
    String? requestedId,
  ) {
    return ResolvedQualityGateSource<T>(
      sourceType: type,
      resolutionMode: QualityGateSourceResolutionMode.unavailable,
      state: ResolvedQualityGateSourceState.unavailable,
      requestedId: requestedId,
    );
  }

  ResolvedQualityGateSource<T> _notRequested<T>(QualityGateSourceType type) {
    return ResolvedQualityGateSource<T>(
      sourceType: type,
      resolutionMode: QualityGateSourceResolutionMode.unavailable,
      state: ResolvedQualityGateSourceState.notRequested,
    );
  }

  QualityGateSourceReference _metricsRef(
    MetricsSnapshot s,
    QualityGateSourceResolutionMode mode,
  ) =>
      QualityGateSourceReference(
        sourceType: QualityGateSourceType.metrics,
        resolutionMode: mode,
        resolvedId: s.metadata.snapshotId,
        fingerprint: s.metadata.sourceGraphFingerprint,
        projectId: s.metadata.projectId,
        commitId: s.metadata.gitRef,
        schemaVersion: s.metadata.metricsSchemaVersion,
        calculationVersion: s.metadata.metricsCalculationVersion,
        availability: QualityGateSourceAvailability.available,
        compatibility: QualityGateCompatibilityStatus.compatible,
      );

  QualityGateSourceReference _scoreRef(
    EngineeringScoreSnapshot s,
    QualityGateSourceResolutionMode mode,
  ) =>
      QualityGateSourceReference(
        sourceType: QualityGateSourceType.score,
        resolutionMode: mode,
        resolvedId: s.metadata.scoreSnapshotId,
        fingerprint: s.metadata.scoreFingerprint,
        projectId: s.metadata.projectId,
        branch: s.metadata.branch,
        commitId: s.metadata.gitRef,
        policyId: s.metadata.policyId,
        policyVersion: s.metadata.policyVersion,
        schemaVersion: s.metadata.scoreSchemaVersion,
        calculationVersion: s.metadata.scoreCalculationVersion,
        availability: QualityGateSourceAvailability.available,
        compatibility: QualityGateCompatibilityStatus.compatible,
      );

  QualityGateSourceReference _mesRef(
    MESSnapshot s,
    QualityGateSourceResolutionMode mode,
  ) =>
      QualityGateSourceReference(
        sourceType: QualityGateSourceType.mes,
        resolutionMode: mode,
        resolvedId: s.metadata.mesSnapshotId,
        fingerprint: s.metadata.mesFingerprint,
        projectId: s.metadata.projectId,
        branch: s.metadata.branch,
        commitId: s.metadata.gitRef,
        policyId: s.metadata.policyId,
        policyVersion: s.metadata.policyVersion,
        schemaVersion: s.metadata.mesSchemaVersion,
        calculationVersion: s.metadata.mesCalculationVersion,
        availability: QualityGateSourceAvailability.available,
        compatibility: _mesCompatibility(s),
      );

  QualityGateCompatibilityStatus _mesCompatibility(MESSnapshot s) {
    switch (s.metadata.compatibilityStatus) {
      case MESCompatibilityStatus.compatible:
        return QualityGateCompatibilityStatus.compatible;
      case MESCompatibilityStatus.partiallyCompatible:
        return QualityGateCompatibilityStatus.partiallyCompatible;
      case MESCompatibilityStatus.incompatible:
        return QualityGateCompatibilityStatus.incompatible;
      case MESCompatibilityStatus.unknown:
        return QualityGateCompatibilityStatus.unknown;
    }
  }

  QualityGateSourceReference _telemetryRef(
    TelemetrySnapshot s,
    QualityGateSourceResolutionMode mode,
  ) =>
      QualityGateSourceReference(
        sourceType: QualityGateSourceType.telemetry,
        resolutionMode: mode,
        resolvedId: s.metadata.telemetrySnapshotId,
        fingerprint: s.metadata.telemetryFingerprint,
        projectId: s.metadata.projectId,
        schemaVersion: s.metadata.telemetrySchemaVersion,
        calculationVersion: s.metadata.telemetryCalculationVersion,
        availability: QualityGateSourceAvailability.available,
        compatibility: QualityGateCompatibilityStatus.compatible,
      );

  QualityGateSourceReference _dashboardRef(
    DashboardSnapshot s,
    QualityGateSourceResolutionMode mode,
  ) =>
      QualityGateSourceReference(
        sourceType: QualityGateSourceType.dashboard,
        resolutionMode: mode,
        resolvedId: s.metadata.dashboardSnapshotId,
        fingerprint: s.metadata.dashboardFingerprint,
        projectId: s.metadata.projectId,
        branch: s.metadata.branch,
        commitId: s.metadata.gitRef,
        schemaVersion: s.metadata.dashboardSchemaVersion,
        calculationVersion: s.metadata.dashboardCalculationVersion,
        availability: QualityGateSourceAvailability.available,
        compatibility: QualityGateCompatibilityStatus.compatible,
      );

  QualityGateSourceReference _unavailableRef(
    QualityGateSourceType type,
    String artifactId,
    QualityGateSourceResolutionMode mode,
  ) =>
      QualityGateSourceReference(
        sourceType: type,
        resolutionMode: mode,
        requestedId: artifactId,
        resolvedId: artifactId,
        availability: QualityGateSourceAvailability.unavailable,
        compatibility: QualityGateCompatibilityStatus.unknown,
        limitations: const ['source unavailable'],
      );
}
