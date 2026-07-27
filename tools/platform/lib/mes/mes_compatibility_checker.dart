import '../metrics/metrics_definitions.dart';
import '../models/mes/mes_enums.dart';
import '../models/mes/mes_policy.dart';
import '../models/metrics/metrics_snapshot.dart';

/// Checks compatibility between MES policy and input evidence.
class MESCompatibilityChecker {
  const MESCompatibilityChecker();

  MESCompatibilityStatus check({
    required MESPolicy policy,
    required MetricsSnapshot metricsSnapshot,
    required bool strict,
  }) {
    final schemaVersion = metricsSnapshot.metadata.metricsSchemaVersion;
    if (schemaVersion > 1 && strict) {
      return MESCompatibilityStatus.incompatible;
    }
    if (schemaVersion > 1) {
      return MESCompatibilityStatus.partiallyCompatible;
    }

    final knownMetrics = MetricsDefinitions.all.keys;
    var unknownCount = 0;
    for (final dim in policy.dimensions) {
      for (final req in dim.metricRequirements) {
        if (!req.metricId.startsWith('history.') &&
            !knownMetrics.contains(req.metricId)) {
          unknownCount++;
        }
      }
    }
    if (unknownCount > 0 && strict) {
      return MESCompatibilityStatus.incompatible;
    }
    if (unknownCount > 0) {
      return MESCompatibilityStatus.partiallyCompatible;
    }
    return MESCompatibilityStatus.compatible;
  }
}
