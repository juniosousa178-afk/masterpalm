import '../../models/metrics/metric_availability.dart';
import '../../models/metrics/metric_value.dart';
import '../../models/metrics/metrics_snapshot.dart';
import '../report_input.dart';

/// Converts [MetricsSnapshot] into [MetricsReportInputData].
class MetricsReportSource {
  const MetricsReportSource();

  MetricsReportInputData fromSnapshot(MetricsSnapshot snapshot) {
    final available = snapshot.metrics
        .where((m) => m.availability == MetricAvailability.available)
        .length;
    final highlights = snapshot.metrics
        .where((m) => m.availability == MetricAvailability.available)
        .take(10)
        .map((m) => '${m.definition.id}: ${_valueLabel(m.value)}')
        .toList();

    return MetricsReportInputData(
      snapshotId: snapshot.metadata.snapshotId,
      metricCount: snapshot.metadata.metricCount,
      availableCount: available,
      unavailableCount: snapshot.metadata.unavailableMetricCount,
      highlights: highlights,
    );
  }

  MetricsReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(MetricsSnapshot.fromJson(json));
  }

  String _valueLabel(MetricValue? value) {
    if (value == null) return 'n/a';
    return switch (value) {
      IntegerMetricValue(:final value) => value.toString(),
      DecimalMetricValue(:final value) => value.toString(),
      PercentageMetricValue(:final value) => value.toString(),
      BooleanMetricValue(:final value) => value.toString(),
      TextMetricValue(:final value) => value,
      DistributionMetricValue() => 'distribution',
      IntegerSeriesMetricValue() => 'series',
      DecimalSeriesMetricValue() => 'series',
    };
  }
}
