import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_snapshot.dart';
import '../models/history/history_compatibility.dart';
import '../models/mes/mes_enums.dart';
import '../models/mes/mes_snapshot.dart';
import '../models/metrics/metric_availability.dart';
import '../models/metrics/metric_record.dart';
import '../models/metrics/metric_value.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/observability/telemetry_enums.dart';
import '../models/observability/telemetry_snapshot.dart';
import '../models/quality_gate/quality_gate_enums.dart';
import '../models/quality_gate/quality_gate_evidence.dart';
import '../models/quality_gate/quality_gate_messages.dart';
import '../models/quality_gate/quality_gate_policy.dart';
import '../models/quality_gate/quality_gate_rule_value.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_snapshot.dart';
import 'resolved_quality_gate_sources.dart';

/// Resolves a typed rule target from published artifacts.
abstract class QualityGateTargetResolver {
  Set<QualityGateRuleTarget> get supportedTargets;

  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  );
}

/// Registry mapping rule targets to domain resolvers.
class QualityGateTargetRegistry {
  QualityGateTargetRegistry({
    List<QualityGateTargetResolver>? resolvers,
  }) : _resolvers = resolvers ?? _defaultResolvers();

  final List<QualityGateTargetResolver> _resolvers;
  late final Map<QualityGateRuleTarget, QualityGateTargetResolver> _byTarget =
      _buildIndex();

  static List<QualityGateTargetResolver> _defaultResolvers() => [
        GuardianQualityGateTargetResolver(),
        MetricsQualityGateTargetResolver(),
        ScoreQualityGateTargetResolver(),
        MESQualityGateTargetResolver(),
        HistoryQualityGateTargetResolver(),
        TelemetryQualityGateTargetResolver(),
        DashboardQualityGateTargetResolver(),
        CrossArtifactQualityGateTargetResolver(),
      ];

  Map<QualityGateRuleTarget, QualityGateTargetResolver> _buildIndex() {
    final index = <QualityGateRuleTarget, QualityGateTargetResolver>{};
    for (final resolver in _resolvers) {
      for (final target in resolver.supportedTargets) {
        index[target] = resolver;
      }
    }
    return index;
  }

  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final resolver = _byTarget[rule.target];
    if (resolver == null) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unsupported,
        evidenceType: QualityGateEvidenceType.unavailable,
        limitations: [],
      );
    }
    return resolver.resolve(rule, sources, context);
  }
}

class GuardianQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.guardianDecision,
        QualityGateRuleTarget.guardianRiskLevel,
        QualityGateRuleTarget.guardianViolationCount,
        QualityGateRuleTarget.guardianCriticalViolationCount,
        QualityGateRuleTarget.guardianWarningCount,
        QualityGateRuleTarget.guardianRuleStatus,
        QualityGateRuleTarget.guardianCompatibility,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.guardian;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final map = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    switch (rule.target) {
      case QualityGateRuleTarget.guardianDecision:
        final raw = map['decision']?.toString() ?? '';
        return _resolved(
          QualityGateStringValue(normalizeGuardianDecision(raw)),
          ref,
        );
      case QualityGateRuleTarget.guardianRiskLevel:
        final risk = map['risk'];
        final level = risk is Map ? risk['overall']?.toString() : null;
        if (level == null) return _unavailable(source);
        return _resolved(QualityGateStringValue(level), ref);
      case QualityGateRuleTarget.guardianViolationCount:
        return _resolved(
          QualityGateIntegerValue(_violations(map).length),
          ref,
        );
      case QualityGateRuleTarget.guardianCriticalViolationCount:
        return _resolved(
          QualityGateIntegerValue(_criticalViolations(map).length),
          ref,
        );
      case QualityGateRuleTarget.guardianWarningCount:
        final warnings = map['warnings'];
        final count = warnings is List ? warnings.length : 0;
        return _resolved(QualityGateIntegerValue(count), ref);
      case QualityGateRuleTarget.guardianRuleStatus:
        final ruleId = rule.selector.guardianRuleId;
        if (ruleId == null || ruleId.isEmpty) {
          return _selectorMissing('guardianRuleId');
        }
        final violation =
            _violations(map).cast<Map<String, dynamic>?>().firstWhere(
                  (v) => v?['code']?.toString() == ruleId,
                  orElse: () => null,
                );
        if (violation == null) {
          return _resolved(const QualityGateStringValue('passed'), ref);
        }
        return _resolved(
          QualityGateStringValue(violation['severity']?.toString() ?? 'failed'),
          ref,
        );
      case QualityGateRuleTarget.guardianCompatibility:
        final compatible = map['compatibility']?.toString().toLowerCase();
        if (compatible == null) {
          return _resolved(const QualityGateBooleanValue(true), ref);
        }
        return _resolved(
          QualityGateBooleanValue(
            compatible == 'compatible' || compatible == 'true',
          ),
          ref,
        );
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }

  List<dynamic> _violations(Map<String, dynamic> map) {
    final violations = map['violations'];
    return violations is List ? violations : const [];
  }

  List<dynamic> _criticalViolations(Map<String, dynamic> map) {
    return _violations(map).where((v) {
      if (v is! Map) return false;
      final severity = v['severity']?.toString().toLowerCase() ?? '';
      return severity == 'critical' ||
          severity == 'blocking' ||
          severity == 'red';
    }).toList();
  }
}

class MetricsQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.metricValue,
        QualityGateRuleTarget.metricAvailability,
        QualityGateRuleTarget.metricCoverage,
        QualityGateRuleTarget.cycleCount,
        QualityGateRuleTarget.criticalCycleCount,
        QualityGateRuleTarget.componentCount,
        QualityGateRuleTarget.isolatedComponentCount,
        QualityGateRuleTarget.dependencyCount,
        QualityGateRuleTarget.maximumFanIn,
        QualityGateRuleTarget.maximumFanOut,
        QualityGateRuleTarget.graphDensity,
      };

  static const _fixedMetricIds = {
    QualityGateRuleTarget.cycleCount: 'graph.cycle.count',
    QualityGateRuleTarget.componentCount: 'graph.node.count',
    QualityGateRuleTarget.isolatedComponentCount:
        'graph.component.isolated_count',
    QualityGateRuleTarget.dependencyCount: 'graph.edge.count',
    QualityGateRuleTarget.maximumFanIn: 'graph.degree.fan_in.max',
    QualityGateRuleTarget.maximumFanOut: 'graph.degree.fan_out.max',
    QualityGateRuleTarget.graphDensity: 'graph.density',
  };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.metrics;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final snapshot = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    if (rule.target == QualityGateRuleTarget.criticalCycleCount) {
      return QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unsupported,
        evidenceType: QualityGateEvidenceType.unavailable,
        limitations: [
          QualityGateLimitation(
            limitationId: 'metrics.criticalCycleCount.unsupported',
            type: QualityGateLimitationType.providerCapabilityGap,
            severity: QualityGateRuleSeverity.warning,
            description:
                'criticalCycleCount has no authoritative metrics source; '
                'graph.cycle.count measures total cycles, not critical cycles',
            impact: 'QG011 cannot evaluate critical cycles authoritatively',
            resolvable: false,
          ),
        ],
      );
    }

    if (rule.target == QualityGateRuleTarget.metricCoverage) {
      final total = snapshot.metadata.metricCount;
      final unavailable = snapshot.metadata.unavailableMetricCount;
      if (total <= 0) {
        return _resolved(const QualityGatePercentageValue(0), ref);
      }
      final coverage = ((total - unavailable) / total) * 100;
      return _resolved(QualityGatePercentageValue(coverage), ref);
    }

    final metricId = rule.target == QualityGateRuleTarget.metricValue
        ? rule.selector.metricId
        : _fixedMetricIds[rule.target];
    if (metricId == null || metricId.isEmpty) {
      return _selectorMissing('metricId');
    }

    final record = _findMetric(snapshot, metricId);
    if (record == null) {
      return _unavailable(source);
    }

    if (rule.target == QualityGateRuleTarget.metricAvailability) {
      return _resolved(
        QualityGateStringValue(record.availability.wireName),
        ref,
      );
    }

    if (record.availability != MetricAvailability.available) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unavailable,
        evidenceType: QualityGateEvidenceType.unavailable,
      );
    }

    final value = _metricValue(record);
    if (value == null) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unavailable,
      );
    }
    return _resolved(value, ref);
  }
}

class ScoreQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.engineeringScoreGlobal,
        QualityGateRuleTarget.engineeringScoreDimension,
        QualityGateRuleTarget.engineeringScoreCoverage,
        QualityGateRuleTarget.engineeringScoreConfidence,
        QualityGateRuleTarget.engineeringScoreCompatibility,
        QualityGateRuleTarget.engineeringScoreEligibility,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.score;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final snapshot = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    switch (rule.target) {
      case QualityGateRuleTarget.engineeringScoreGlobal:
        return _resolved(
          QualityGateDecimalValue(snapshot.overallScore.value),
          ref,
        );
      case QualityGateRuleTarget.engineeringScoreDimension:
        final dimensionId = rule.selector.dimensionId;
        if (dimensionId == null || dimensionId.isEmpty) {
          return _selectorMissing('dimensionId');
        }
        final dimension =
            snapshot.dimensions.cast<ScoreDimensionResult?>().firstWhere(
                  (d) => d?.dimensionId == dimensionId,
                  orElse: () => null,
                );
        if (dimension == null || dimension.normalizedScore == null) {
          return _unavailable(source);
        }
        return _resolved(
          QualityGateDecimalValue(dimension.normalizedScore!),
          ref,
        );
      case QualityGateRuleTarget.engineeringScoreCoverage:
        return _resolved(
          QualityGatePercentageValue(snapshot.coverage.coveragePercentage),
          ref,
        );
      case QualityGateRuleTarget.engineeringScoreConfidence:
        return _resolved(
          QualityGateEnumValue(
            domain: 'scoreConfidence',
            value: snapshot.metadata.confidence.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.engineeringScoreCompatibility:
        return _resolved(
          QualityGateEnumValue(
            domain: 'scoreCompatibility',
            value: snapshot.metadata.compatibilityStatus.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.engineeringScoreEligibility:
        final eligible = snapshot.metadata.status == ScoreStatus.success ||
            snapshot.metadata.status == ScoreStatus.partial;
        return _resolved(QualityGateBooleanValue(eligible), ref);
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }
}

class MESQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.mesGlobalScore,
        QualityGateRuleTarget.mesBand,
        QualityGateRuleTarget.mesDimensionScore,
        QualityGateRuleTarget.mesCoverage,
        QualityGateRuleTarget.mesConfidence,
        QualityGateRuleTarget.mesEligibility,
        QualityGateRuleTarget.mesCompatibility,
        QualityGateRuleTarget.mesPolicyId,
        QualityGateRuleTarget.mesPolicyVersion,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.mes;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final snapshot = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    switch (rule.target) {
      case QualityGateRuleTarget.mesGlobalScore:
        return _resolved(
          QualityGateDecimalValue(snapshot.mesValue.value),
          ref,
        );
      case QualityGateRuleTarget.mesBand:
        final band = snapshot.band?.bandId;
        if (band == null) return _unavailable(source);
        return _resolved(QualityGateStringValue(band), ref);
      case QualityGateRuleTarget.mesDimensionScore:
        final dimensionId = rule.selector.dimensionId;
        if (dimensionId == null || dimensionId.isEmpty) {
          return _selectorMissing('dimensionId');
        }
        final dimension =
            snapshot.dimensions.cast<MESDimensionResult?>().firstWhere(
                  (d) => d?.dimensionId == dimensionId,
                  orElse: () => null,
                );
        if (dimension == null || dimension.normalizedScore == null) {
          return _unavailable(source);
        }
        return _resolved(
          QualityGateDecimalValue(dimension.normalizedScore!),
          ref,
        );
      case QualityGateRuleTarget.mesCoverage:
        return _resolved(
          QualityGatePercentageValue(snapshot.coverage.dimensionCoverage),
          ref,
        );
      case QualityGateRuleTarget.mesConfidence:
        return _resolved(
          QualityGateEnumValue(
            domain: 'mesConfidence',
            value: snapshot.confidence.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.mesEligibility:
        return _resolved(
          QualityGateEnumValue(
            domain: 'mesEligibility',
            value: snapshot.eligibility.status.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.mesCompatibility:
        return _resolved(
          QualityGateEnumValue(
            domain: 'mesCompatibility',
            value: snapshot.metadata.compatibilityStatus.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.mesPolicyId:
        return _resolved(
          QualityGateStringValue(snapshot.metadata.policyId),
          ref,
        );
      case QualityGateRuleTarget.mesPolicyVersion:
        return _resolved(
          QualityGateIntegerValue(snapshot.metadata.policyVersion),
          ref,
        );
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }
}

class HistoryQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.historyChangeCount,
        QualityGateRuleTarget.historyAddedCount,
        QualityGateRuleTarget.historyRemovedCount,
        QualityGateRuleTarget.historyModifiedCount,
        QualityGateRuleTarget.historyRegressionCount,
        QualityGateRuleTarget.historyArtifactCompatibility,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.history;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final diff = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    switch (rule.target) {
      case QualityGateRuleTarget.historyChangeCount:
        return _resolved(
          QualityGateIntegerValue(diff.summary.totalChanges),
          ref,
        );
      case QualityGateRuleTarget.historyAddedCount:
        return _resolved(
          QualityGateIntegerValue(diff.summary.addedCount),
          ref,
        );
      case QualityGateRuleTarget.historyRemovedCount:
        return _resolved(
          QualityGateIntegerValue(diff.summary.removedCount),
          ref,
        );
      case QualityGateRuleTarget.historyModifiedCount:
        return _resolved(
          QualityGateIntegerValue(diff.summary.changedCount),
          ref,
        );
      case QualityGateRuleTarget.historyRegressionCount:
        final regressions = diff.changes
            .where((c) => c.metadata['regression'] == 'true')
            .length;
        return QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.resolved,
          actualValue: QualityGateIntegerValue(regressions),
          sourceReference: ref,
          evidenceType: QualityGateEvidenceType.derived,
          limitations: [
            QualityGateLimitation(
              limitationId: 'history.regressionCount.derived',
              type: QualityGateLimitationType.providerCapabilityGap,
              severity: QualityGateRuleSeverity.advisory,
              description:
                  'historyRegressionCount is derived from change metadata '
                  'regression=true; HistoryDiff has no authoritative '
                  'regressionCount field',
              impact: 'Regression count is indicative, not authoritative',
              resolvable: false,
            ),
          ],
        );
      case QualityGateRuleTarget.historyArtifactCompatibility:
        return _resolved(
          QualityGateEnumValue(
            domain: 'historyCompatibility',
            value: diff.compatibility.status.wireName,
          ),
          ref,
        );
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }
}

class TelemetryQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.telemetryFailureCount,
        QualityGateRuleTarget.telemetryIncompleteOperationCount,
        QualityGateRuleTarget.telemetrySuccessRate,
        QualityGateRuleTarget.telemetryEventCoverage,
        QualityGateRuleTarget.telemetryTerminalCoverage,
        QualityGateRuleTarget.telemetryCompatibility,
        QualityGateRuleTarget.telemetrySnapshotStatus,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.telemetry;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final snapshot = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    switch (rule.target) {
      case QualityGateRuleTarget.telemetryFailureCount:
        return _resolved(
          QualityGateIntegerValue(snapshot.coverage.failedOperationCount),
          ref,
        );
      case QualityGateRuleTarget.telemetryIncompleteOperationCount:
        return _resolved(
          QualityGateIntegerValue(snapshot.coverage.incompleteOperationCount),
          ref,
        );
      case QualityGateRuleTarget.telemetrySuccessRate:
        return _resolved(
          QualityGatePercentageValue(snapshot.summary.successRatePercentage),
          ref,
        );
      case QualityGateRuleTarget.telemetryEventCoverage:
        return _resolved(
          QualityGatePercentageValue(snapshot.coverage.eventCoveragePercentage),
          ref,
        );
      case QualityGateRuleTarget.telemetryTerminalCoverage:
        return _resolved(
          QualityGatePercentageValue(
            snapshot.coverage.terminalEventCoveragePercentage,
          ),
          ref,
        );
      case QualityGateRuleTarget.telemetryCompatibility:
        return _resolved(
          QualityGateEnumValue(
            domain: 'telemetryCompatibility',
            value: snapshot.compatibility.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.telemetrySnapshotStatus:
        return _resolved(
          QualityGateEnumValue(
            domain: 'telemetrySnapshotStatus',
            value: snapshot.metadata.status.wireName,
          ),
          ref,
        );
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }
}

class DashboardQualityGateTargetResolver implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.dashboardStatus,
        QualityGateRuleTarget.dashboardFreshness,
        QualityGateRuleTarget.dashboardCompatibility,
        QualityGateRuleTarget.dashboardWarningCount,
        QualityGateRuleTarget.dashboardErrorCount,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final source = sources.dashboard;
    if (!source.isAvailable) {
      return _unavailable(source);
    }
    final snapshot = source.resolvedArtifact!;
    final ref = _sourceRef(source);

    switch (rule.target) {
      case QualityGateRuleTarget.dashboardStatus:
        return _resolved(
          QualityGateEnumValue(
            domain: 'dashboardStatus',
            value: snapshot.metadata.status.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.dashboardFreshness:
        return _resolved(
          QualityGateEnumValue(
            domain: 'dashboardFreshness',
            value: snapshot.metadata.freshness.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.dashboardCompatibility:
        return _resolved(
          QualityGateEnumValue(
            domain: 'dashboardCompatibility',
            value: snapshot.metadata.compatibility.wireName,
          ),
          ref,
        );
      case QualityGateRuleTarget.dashboardWarningCount:
        return _resolved(
          QualityGateIntegerValue(snapshot.metadata.warningCount),
          ref,
        );
      case QualityGateRuleTarget.dashboardErrorCount:
        return _resolved(
          QualityGateIntegerValue(snapshot.metadata.errorCount),
          ref,
        );
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }
}

class CrossArtifactQualityGateTargetResolver
    implements QualityGateTargetResolver {
  @override
  Set<QualityGateRuleTarget> get supportedTargets => {
        QualityGateRuleTarget.sourceProjectConsistency,
        QualityGateRuleTarget.sourceCommitConsistency,
        QualityGateRuleTarget.sourcePolicyConsistency,
        QualityGateRuleTarget.sourceSchemaCompatibility,
        QualityGateRuleTarget.sourceFreshness,
        QualityGateRuleTarget.requiredSourcesAvailable,
      };

  @override
  QualityGateTargetResolution resolve(
    QualityGateRule rule,
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    switch (rule.target) {
      case QualityGateRuleTarget.sourceProjectConsistency:
        return _projectConsistency(sources, context);
      case QualityGateRuleTarget.sourceCommitConsistency:
        return _commitConsistency(sources, context);
      case QualityGateRuleTarget.sourcePolicyConsistency:
        return _policyConsistency(sources, context);
      case QualityGateRuleTarget.sourceSchemaCompatibility:
        return _schemaCompatibility(sources);
      case QualityGateRuleTarget.sourceFreshness:
        return _freshness(sources, context);
      case QualityGateRuleTarget.requiredSourcesAvailable:
        return _requiredSources(sources, context);
      default:
        return const QualityGateTargetResolution(
          status: QualityGateTargetResolutionStatus.unsupported,
        );
    }
  }

  QualityGateTargetResolution _projectConsistency(
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final projectIds = <String>{};
    for (final source in sources.allSources) {
      if (source.state == ResolvedQualityGateSourceState.notRequested) {
        continue;
      }
      final projectId = source.projectId ?? _projectFromArtifact(source);
      if (projectId != null && projectId.isNotEmpty) {
        projectIds.add(projectId);
      }
    }
    if (projectIds.isEmpty) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unavailable,
      );
    }
    final consistent = projectIds.length == 1 &&
        (projectIds.first == context.projectId || projectIds.length == 1);
    return QualityGateTargetResolution(
      status: QualityGateTargetResolutionStatus.resolved,
      actualValue: QualityGateBooleanValue(consistent),
      evidenceType: QualityGateEvidenceType.derived,
    );
  }

  QualityGateTargetResolution _commitConsistency(
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    if (context.commitId == null || context.commitId!.isEmpty) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.notApplicable,
        notApplicable: true,
      );
    }
    final commits = <String>{};
    for (final source in sources.allSources) {
      if (source.state == ResolvedQualityGateSourceState.notRequested) {
        continue;
      }
      final commit = source.commitId;
      if (commit != null && commit.isNotEmpty) {
        commits.add(commit);
      }
    }
    if (commits.isEmpty) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unavailable,
      );
    }
    final consistent = commits.length == 1 && commits.first == context.commitId;
    return QualityGateTargetResolution(
      status: QualityGateTargetResolutionStatus.resolved,
      actualValue: QualityGateBooleanValue(consistent),
      evidenceType: QualityGateEvidenceType.derived,
    );
  }

  QualityGateTargetResolution _policyConsistency(
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final policyKeys = <String>{};
    for (final source in [sources.score, sources.mes]) {
      if (!source.isAvailable) continue;
      final policyId = source.policyId;
      final version = source.policyVersion;
      if (policyId != null && version != null) {
        policyKeys.add('$policyId:v$version');
      }
    }
    if (policyKeys.isEmpty) {
      return const QualityGateTargetResolution(
        status: QualityGateTargetResolutionStatus.unavailable,
      );
    }
    return QualityGateTargetResolution(
      status: QualityGateTargetResolutionStatus.resolved,
      actualValue: QualityGateBooleanValue(policyKeys.length == 1),
      evidenceType: QualityGateEvidenceType.derived,
    );
  }

  QualityGateTargetResolution _schemaCompatibility(
    ResolvedQualityGateSources sources,
  ) {
    final incompatible = sources.sourceReferences
        .where(
          (r) => r.compatibility == QualityGateCompatibilityStatus.incompatible,
        )
        .isNotEmpty;
    return QualityGateTargetResolution(
      status: QualityGateTargetResolutionStatus.resolved,
      actualValue: QualityGateBooleanValue(!incompatible),
      evidenceType: QualityGateEvidenceType.derived,
    );
  }

  QualityGateTargetResolution _freshness(
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final hasUnavailable = sources.allSources.any(
      (s) => s.state == ResolvedQualityGateSourceState.unavailable,
    );
    return QualityGateTargetResolution(
      status: QualityGateTargetResolutionStatus.resolved,
      actualValue: QualityGateBooleanValue(!hasUnavailable),
      evidenceType: QualityGateEvidenceType.contextual,
    );
  }

  QualityGateTargetResolution _requiredSources(
    ResolvedQualityGateSources sources,
    QualityGateEvaluationContext context,
  ) {
    final missing = context.requiredSourceTypes.where((type) {
      final source = sources.allSources.firstWhere((s) => s.sourceType == type);
      return !source.isAvailable;
    }).toList();
    return QualityGateTargetResolution(
      status: QualityGateTargetResolutionStatus.resolved,
      actualValue: QualityGateBooleanValue(missing.isEmpty),
      evidenceType: QualityGateEvidenceType.operational,
    );
  }

  String? _projectFromArtifact(ResolvedQualityGateSource<dynamic> source) {
    final artifact = source.resolvedArtifact;
    if (artifact is MetricsSnapshot) {
      return artifact.metadata.projectId;
    }
    if (artifact is EngineeringScoreSnapshot) {
      return artifact.metadata.projectId;
    }
    if (artifact is MESSnapshot) {
      return artifact.metadata.projectId;
    }
    if (artifact is DashboardSnapshot) {
      return artifact.metadata.projectId;
    }
    if (artifact is TelemetrySnapshot) {
      return artifact.metadata.projectId;
    }
    return source.projectId;
  }
}

MetricRecord? _findMetric(MetricsSnapshot snapshot, String metricId) {
  for (final metric in snapshot.metrics) {
    if (metric.definition.id == metricId) {
      return metric;
    }
  }
  return null;
}

QualityGateRuleValue? _metricValue(MetricRecord record) {
  final value = record.value;
  return switch (value) {
    IntegerMetricValue(:final value) => QualityGateIntegerValue(value),
    DecimalMetricValue(:final value) => QualityGateDecimalValue(value),
    PercentageMetricValue(:final value) => QualityGatePercentageValue(value),
    BooleanMetricValue(:final value) => QualityGateBooleanValue(value),
    TextMetricValue(:final value) => QualityGateStringValue(value),
    _ => null,
  };
}

QualityGateSourceReference? _sourceRef(
    ResolvedQualityGateSource<dynamic> source) {
  return QualityGateSourceReference(
    sourceType: source.sourceType,
    resolutionMode: source.resolutionMode,
    requestedId: source.requestedId,
    resolvedId: source.resolvedId,
    fingerprint: source.fingerprint,
    projectId: source.projectId,
    commitId: source.commitId,
    branch: source.branch,
    policyId: source.policyId,
    policyVersion: source.policyVersion,
    schemaVersion: source.schemaVersion,
    calculationVersion: source.calculationVersion,
    availability: source.isAvailable
        ? QualityGateSourceAvailability.available
        : QualityGateSourceAvailability.unavailable,
    compatibility: QualityGateCompatibilityStatus.compatible,
  );
}

QualityGateTargetResolution _resolved(
  QualityGateRuleValue value,
  QualityGateSourceReference? ref,
) {
  return QualityGateTargetResolution(
    status: QualityGateTargetResolutionStatus.resolved,
    actualValue: value,
    sourceReference: ref,
  );
}

QualityGateTargetResolution _unavailable(
    ResolvedQualityGateSource<dynamic> source) {
  return QualityGateTargetResolution(
    status: QualityGateTargetResolutionStatus.unavailable,
    sourceReference: _sourceRef(source),
    evidenceType: QualityGateEvidenceType.unavailable,
  );
}

QualityGateTargetResolution _selectorMissing(String selectorName) {
  return QualityGateTargetResolution(
    status: QualityGateTargetResolutionStatus.unavailable,
    evidenceType: QualityGateEvidenceType.unavailable,
    limitations: [
      QualityGateLimitation(
        limitationId: 'missing-selector-$selectorName',
        type: QualityGateLimitationType.missingEvidence,
        severity: QualityGateRuleSeverity.warning,
        description: 'Selector $selectorName is required for this target',
        impact: 'Target cannot be resolved',
        resolvable: true,
      ),
    ],
  );
}
