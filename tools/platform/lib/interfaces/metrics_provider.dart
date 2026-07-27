import '../models/metrics/metrics_request.dart';
import '../models/metrics/metrics_snapshot.dart';

/// Contract for metrics calculation through Platform Core.
abstract class MetricsProvider {
  Future<MetricsResult> calculate(MetricsRequest request);

  Future<MetricsSnapshot?> load();

  Future<void> publish(MetricsSnapshot snapshot);

  Future<void> invalidate();

  Set<String> get supportedMetricIds;
}
