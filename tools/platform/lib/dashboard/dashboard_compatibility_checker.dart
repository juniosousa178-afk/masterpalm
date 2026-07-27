import '../models/dashboard/dashboard_enums.dart';
import 'dashboard_source_resolver.dart';

/// Checks compatibility between resolved dashboard sources.
class DashboardCompatibilityChecker {
  const DashboardCompatibilityChecker();

  DashboardCompatibility evaluate(DashboardResolvedSources sources) {
    final refs = sources.references
        .where((r) => r.availability != DashboardAvailability.unavailable)
        .toList();
    if (refs.isEmpty) return DashboardCompatibility.unknown;

    final projectIds = refs.map((r) => r.projectId).toSet();
    if (projectIds.length > 1) return DashboardCompatibility.incompatible;

    final branches = refs
        .map((r) => r.branch)
        .whereType<String>()
        .where((b) => b.isNotEmpty)
        .toSet();
    if (branches.length > 1) return DashboardCompatibility.incompatible;

    final gitRefs = refs
        .map((r) => r.gitRef)
        .whereType<String>()
        .where((g) => g.isNotEmpty)
        .toSet();
    if (gitRefs.length > 1) return DashboardCompatibility.incompatible;

    var partial = false;

    final metrics = sources.metrics;
    final score = sources.score;
    if (metrics != null && score != null) {
      if (score.metadata.sourceMetricsSnapshotId !=
          metrics.metadata.snapshotId) {
        partial = true;
      }
    }

    final mes = sources.mes;
    if (mes != null && score != null) {
      if (mes.metadata.sourceEngineeringScoreSnapshotId !=
          score.metadata.scoreSnapshotId) {
        partial = true;
      }
    }

    if (mes != null && metrics != null) {
      if (mes.metadata.sourceMetricsSnapshotId != metrics.metadata.snapshotId) {
        partial = true;
      }
    }

    if (partial) return DashboardCompatibility.partiallyCompatible;
    return DashboardCompatibility.compatible;
  }
}
