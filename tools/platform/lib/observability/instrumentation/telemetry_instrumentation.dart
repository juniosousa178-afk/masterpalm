import '../../models/observability/telemetry_attributes.dart';
import '../../models/observability/telemetry_enums.dart';
import '../../models/observability/telemetry_event.dart';
import '../clocks/platform_clock.dart';
import '../observability_collector.dart';
import '../telemetry_canonical_serializer.dart';
import '../telemetry_error_sanitizer.dart';
import '../telemetry_event_id_factory.dart';
import '../telemetry_operation_scope.dart';
import '../telemetry_timer.dart';

/// Shared instrumentation utilities for observable provider decorators.
class TelemetryInstrumentation {
  TelemetryInstrumentation({
    required this.collector,
    required this.clock,
    required this.timerFactory,
    TelemetryErrorSanitizer? errorSanitizer,
    TelemetryEventIdFactory? idFactory,
    TelemetryCanonicalSerializer? serializer,
  })  : errorSanitizer = errorSanitizer ?? const TelemetryErrorSanitizer(),
        idFactory = idFactory ?? const TelemetryEventIdFactory(),
        serializer = serializer ?? const TelemetryCanonicalSerializer();

  final ObservabilityCollector collector;
  final PlatformClock clock;
  final TelemetryTimerFactory timerFactory;
  final TelemetryErrorSanitizer errorSanitizer;
  final TelemetryEventIdFactory idFactory;
  final TelemetryCanonicalSerializer serializer;

  int _operationCounter = 0;

  String nextOperationId({
    required TelemetryComponent component,
    required TelemetryOperation operation,
    String? projectId,
  }) {
    _operationCounter++;
    final project = projectId ?? 'platform';
    return 'op:${component.wireName}:${operation.wireName}:$project:$_operationCounter';
  }

  TelemetryCorrelation correlation({
    required String operationId,
    String? projectId,
    String? correlationId,
    List<String> sourceArtifactIds = const [],
  }) {
    return TelemetryCorrelation(
      correlationId: correlationId ?? 'corr:$operationId',
      operationId: operationId,
      projectId: projectId,
    );
  }

  Future<T> observe<T>({
    required TelemetryComponent component,
    required TelemetryOperation operation,
    String? projectId,
    String? correlationId,
    List<TelemetryAttribute> attributes = const [],
    List<TelemetrySourceReference> sourceReferences = const [],
    List<String> sourceArtifactIds = const [],
    required Future<T> Function() action,
    List<String> Function(T result)? resultingArtifactIds,
  }) async {
    final operationId = nextOperationId(
      component: component,
      operation: operation,
      projectId: projectId,
    );
    final corr = TelemetryCorrelation(
      correlationId: correlationId ?? 'corr:$operationId',
      operationId: operationId,
      projectId: projectId,
      sourceArtifactIds: sourceArtifactIds,
    );
    final scope = TelemetryOperationScope(
      collector: collector,
      clock: clock,
      timerFactory: timerFactory,
      errorSanitizer: errorSanitizer,
      idFactory: idFactory,
      serializer: serializer,
      component: component,
      operation: operation,
      correlation: corr,
      startedAt: clock.nowUtcIso(),
      attributes: attributes,
      sourceReferences: sourceReferences,
    );
    await scope.start();
    try {
      final result = await action();
      await scope.complete(
        resultingArtifactIds: resultingArtifactIds?.call(result) ?? const [],
      );
      return result;
    } catch (error, stackTrace) {
      await scope.fail(error, stackTrace);
      rethrow;
    }
  }

  Future<void> observeVoid({
    required TelemetryComponent component,
    required TelemetryOperation operation,
    String? projectId,
    List<TelemetryAttribute> attributes = const [],
    required Future<void> Function() action,
  }) {
    return observe(
      component: component,
      operation: operation,
      projectId: projectId,
      attributes: attributes,
      action: action,
    );
  }
}
