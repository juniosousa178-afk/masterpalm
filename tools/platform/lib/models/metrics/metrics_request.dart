import 'metric_category.dart';
import 'metrics_snapshot.dart';

/// Request to calculate platform metrics.
class MetricsRequest {
  const MetricsRequest({
    required this.projectId,
    this.projectGraph,
    this.metricIds,
    this.categories,
    this.guardianAnalysis,
    this.astReport,
    this.sourceSnapshotId,
    this.gitRef,
    this.depthLimit = 20,
  });

  final String projectId;
  final Map<String, dynamic>? projectGraph;
  final Set<String>? metricIds;
  final Set<MetricCategory>? categories;
  final Map<String, dynamic>? guardianAnalysis;
  final Map<String, dynamic>? astReport;
  final String? sourceSnapshotId;
  final String? gitRef;
  final int depthLimit;

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        if (metricIds != null) 'metricIds': metricIds!.toList()..sort(),
        if (categories != null)
          'categories': categories!.map((c) => c.wireName).toList()..sort(),
        if (sourceSnapshotId != null) 'sourceSnapshotId': sourceSnapshotId,
        if (gitRef != null) 'gitRef': gitRef,
        'depthLimit': depthLimit,
      };
}

/// Status of a metrics calculation run.
enum MetricsResultStatus {
  success,
  partial,
  failure,
}

extension MetricsResultStatusX on MetricsResultStatus {
  String get wireName => name;

  static MetricsResultStatus fromWireName(String value) {
    return MetricsResultStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () =>
          throw FormatException('Unknown MetricsResultStatus: $value'),
    );
  }
}

/// Error for a single metric calculation.
class MetricsCalculationError {
  const MetricsCalculationError({
    required this.metricId,
    required this.message,
    this.code,
  });

  final String metricId;
  final String message;
  final String? code;

  Map<String, dynamic> toJson() => {
        'metricId': metricId,
        'message': message,
        if (code != null) 'code': code,
      };

  factory MetricsCalculationError.fromJson(Map<String, dynamic> json) {
    return MetricsCalculationError(
      metricId: json['metricId'] as String,
      message: json['message'] as String,
      code: json['code'] as String?,
    );
  }
}

/// Result of metrics calculation.
class MetricsResult {
  const MetricsResult({
    required this.status,
    required this.snapshot,
    this.warnings = const [],
    this.errors = const [],
  });

  final MetricsResultStatus status;
  final MetricsSnapshot snapshot;
  final List<String> warnings;
  final List<MetricsCalculationError> errors;
}
