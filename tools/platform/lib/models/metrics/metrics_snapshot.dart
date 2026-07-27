import 'metric_record.dart';
import 'metrics_metadata.dart';

/// Immutable snapshot of calculated metrics.
class MetricsSnapshot {
  const MetricsSnapshot({
    required this.metadata,
    required this.metrics,
  });

  final MetricsMetadata metadata;
  final List<MetricRecord> metrics;

  Map<String, dynamic> toJson() => {
        'metadata': metadata.toJson(),
        'metrics': metrics.map((m) => m.toJson()).toList(),
      };

  factory MetricsSnapshot.fromJson(Map<String, dynamic> json) {
    return MetricsSnapshot(
      metadata: MetricsMetadata.fromJson(
        json['metadata'] as Map<String, dynamic>,
      ),
      metrics: (json['metrics'] as List<dynamic>)
          .map((e) => MetricRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toComparableJson() => {
        'metadata': metadata.toComparableJson(),
        'metrics': metrics.map((m) => m.toJson()).toList(),
      };
}
