import '../exceptions/platform_exception.dart';

/// Metrics Engine specific errors.
class MetricsException extends PlatformException {
  MetricsException(super.message, {super.cause, super.code});
}

class MetricsUnknownMetricException extends MetricsException {
  MetricsUnknownMetricException(String metricId)
      : super('Unknown metric id: $metricId', code: 'unknown_metric');
}

class MetricsGraphException extends MetricsException {
  MetricsGraphException(String message, {Object? cause})
      : super(message, cause: cause, code: 'invalid_graph');
}
