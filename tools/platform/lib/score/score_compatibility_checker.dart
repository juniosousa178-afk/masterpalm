import '../models/metrics/metric_record.dart';
import '../models/metrics/metrics_metadata.dart';
import '../models/metrics/metrics_snapshot.dart';
import '../models/score/score_enums.dart';
import '../models/score/score_policy.dart';

/// Checks compatibility between policy and input evidence.
class ScoreCompatibilityChecker {
  const ScoreCompatibilityChecker();

  ScoreCompatibilityStatus check({
    required ScorePolicy policy,
    required MetricsSnapshot metricsSnapshot,
    bool strict = false,
  }) {
    final reasons = <String>[];

    if (!policy.supportedMetricVersions
        .contains(metricsSnapshot.metadata.metricsCalculationVersion)) {
      reasons.add(
        'metricsCalculationVersion ${metricsSnapshot.metadata.metricsCalculationVersion} not supported',
      );
    }
    if (metricsSnapshot.metadata.metricsSchemaVersion !=
        MetricsMetadata.currentSchemaVersion) {
      reasons.add('metricsSchemaVersion mismatch');
    }

    final requiredMetricIds = <String>{};
    for (final dim in policy.dimensions) {
      for (final rule in dim.rules) {
        if (!rule.metricId.startsWith('history.')) {
          requiredMetricIds.add(rule.metricId);
        }
      }
    }

    var incompatibleCount = 0;
    for (final metricId in requiredMetricIds) {
      MetricRecord? record;
      for (final m in metricsSnapshot.metrics) {
        if (m.definition.id == metricId) {
          record = m;
          break;
        }
      }
      if (record == null) {
        reasons.add('metric not present in snapshot: $metricId');
        incompatibleCount++;
      }
    }

    if (reasons.isEmpty) return ScoreCompatibilityStatus.compatible;
    if (strict || incompatibleCount == requiredMetricIds.length) {
      return ScoreCompatibilityStatus.incompatible;
    }
    if (incompatibleCount > 0) {
      return ScoreCompatibilityStatus.partiallyCompatible;
    }
    return ScoreCompatibilityStatus.unknown;
  }
}
