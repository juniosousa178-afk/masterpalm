import '../models/dashboard/dashboard_enums.dart';
import '../models/dashboard/dashboard_request.dart';
import 'dashboard_source_resolver.dart';

/// Evaluates freshness of dashboard sources against reference time.
class DashboardFreshnessEvaluator {
  const DashboardFreshnessEvaluator();

  DashboardFreshness evaluate({
    required DashboardRequest request,
    required DashboardResolvedSources sources,
  }) {
    final policy = request.freshnessPolicy;
    final reference = DateTime.parse(request.referenceTime).toUtc();
    final timestamps = <DateTime>[];

    for (final ref in sources.references) {
      if (ref.availability == DashboardAvailability.unavailable) continue;
      if (ref.createdAt.trim().isEmpty) continue;
      timestamps.add(DateTime.parse(ref.createdAt).toUtc());
    }

    if (timestamps.isEmpty) return DashboardFreshness.unknown;

    timestamps.sort();
    final oldest = timestamps.first;
    final newest = timestamps.last;
    final skew = newest.difference(oldest).inHours;
    if (skew > policy.maxSourceSkewHours) {
      return DashboardFreshness.mixed;
    }

    final ages =
        timestamps.map((t) => reference.difference(t).inHours).toList();

    final allCurrent =
        ages.every((h) => h >= 0 && h <= policy.currentMaxAgeHours);
    if (allCurrent) return DashboardFreshness.current;

    final allRecent =
        ages.every((h) => h >= 0 && h <= policy.recentMaxAgeHours);
    if (allRecent) return DashboardFreshness.recent;

    final anyStale = ages.any((h) => h > policy.staleAfterHours);
    if (anyStale) return DashboardFreshness.stale;

    return DashboardFreshness.recent;
  }
}
