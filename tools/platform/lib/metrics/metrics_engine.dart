import '../graph/graph_validator.dart';
import '../interfaces/graph_provider.dart';
import '../models/graph/project_graph.dart';
import '../models/metrics/metric_availability.dart';
import '../models/metrics/metric_record.dart';
import '../models/metrics/metrics_metadata.dart';
import '../models/metrics/metrics_request.dart';
import '../models/metrics/metrics_snapshot.dart';
import 'metric_calculator.dart';
import 'metrics_definitions.dart';
import 'metrics_exceptions.dart';
import 'metrics_graph_context.dart';
import 'metrics_registry.dart';
import 'metrics_snapshot_id_factory.dart';
import 'metrics_validator.dart';

/// Coordinates metrics calculation from [ProjectGraph].
class MetricsEngine {
  MetricsEngine({
    MetricsRegistry? registry,
    MetricsValidator? validator,
    MetricsSnapshotIdFactory? idFactory,
    GraphProvider? graphProvider,
  })  : _registry = registry ?? MetricsRegistry(),
        _validator = validator ?? const MetricsValidator(),
        _idFactory = idFactory ?? const MetricsSnapshotIdFactory(),
        _graphProvider = graphProvider;

  final MetricsRegistry _registry;
  final MetricsValidator _validator;
  final MetricsSnapshotIdFactory _idFactory;
  final GraphProvider? _graphProvider;

  Set<String> get supportedMetricIds => _registry.supportedMetricIds;

  Future<MetricsResult> calculate(MetricsRequest request) async {
    final warnings = <String>[];
    final errors = <MetricsCalculationError>[];

    final graph = await _resolveGraph(request);
    final graphValidation = const GraphValidator().validate(graph);
    if (!graphValidation.valid) {
      throw MetricsGraphException(
        'Invalid project graph: ${graphValidation.errors.join('; ')}',
      );
    }

    final effectiveIds = _resolveEffectiveIds(request);

    final context = MetricsCalculationContext(
      graphContext: MetricsGraphContext(graph),
      guardianAnalysis: request.guardianAnalysis,
      astReport: request.astReport,
      depthLimit: request.depthLimit,
      requestedMetricIds: effectiveIds,
    );

    final records = <MetricRecord>[];
    for (final calculator in _registry.calculatorsFor(effectiveIds)) {
      try {
        records.addAll(calculator.calculate(context));
      } catch (e) {
        for (final id in calculator.metricIds.intersection(effectiveIds)) {
          errors.add(MetricsCalculationError(
            metricId: id,
            message: e.toString(),
            code: 'calculation_error',
          ));
          records.add(MetricRecord(
            definition: MetricsDefinitions.all[id]!,
            availability: MetricAvailability.calculationError,
            message: e.toString(),
          ));
        }
      }
    }

    final producedIds = records.map((r) => r.definition.id).toSet();
    for (final id in effectiveIds) {
      if (!producedIds.contains(id)) {
        records.add(MetricRecord(
          definition: MetricsDefinitions.all[id]!,
          availability: MetricAvailability.unsupported,
          message: 'No calculator produced metric $id',
        ));
      }
    }

    final sortedRecords = records.toList()
      ..sort((a, b) => a.definition.id.compareTo(b.definition.id));

    final unavailableCount = sortedRecords
        .where((r) => r.availability != MetricAvailability.available)
        .length;

    if (sortedRecords.any((r) => r.message?.contains('Depth limit') ?? false)) {
      warnings.add('Bounded depth limit may prevent broader depth conclusions');
    }

    final fingerprint = _idFactory.graphFingerprint(graph);
    final snapshot = MetricsSnapshot(
      metadata: MetricsMetadata(
        snapshotId: _idFactory.create(
          projectId: request.projectId,
          sourceGraphFingerprint: fingerprint,
        ),
        metricsSchemaVersion: MetricsMetadata.currentSchemaVersion,
        metricsCalculationVersion: MetricsMetadata.currentCalculationVersion,
        metricsCanonicalizationVersion:
            MetricsMetadata.currentCanonicalizationVersion,
        fingerprintAlgorithm: MetricsMetadata.fingerprintAlgorithmName,
        projectId: request.projectId,
        sourceGraphFingerprint: fingerprint,
        metricCount: sortedRecords.length,
        unavailableMetricCount: unavailableCount,
        warningCount: warnings.length,
        sourceSnapshotId: request.sourceSnapshotId,
        gitRef: request.gitRef,
      ),
      metrics: sortedRecords,
    );

    final validation = _validator.validate(snapshot);
    if (!validation.isValid) {
      throw MetricsException(
        'Metrics validation failed: ${validation.errors.join('; ')}',
        code: 'validation_failed',
      );
    }

    final status = errors.isNotEmpty
        ? MetricsResultStatus.partial
        : unavailableCount > 0
            ? MetricsResultStatus.partial
            : MetricsResultStatus.success;

    return MetricsResult(
      status: status,
      snapshot: snapshot,
      warnings: [...warnings, ...validation.warnings],
      errors: errors,
    );
  }

  Set<String> _resolveEffectiveIds(MetricsRequest request) {
    if (request.metricIds != null && request.metricIds!.isNotEmpty) {
      return _registry.resolveRequestedMetricIds(metricIds: request.metricIds);
    }
    if (request.categories != null && request.categories!.isNotEmpty) {
      return _registry.resolveRequestedMetricIds(
        categories: request.categories,
      );
    }
    final ids = Set<String>.from(MetricsDefinitions.defaultMetricIds);
    if (request.guardianAnalysis != null &&
        request.guardianAnalysis!.isNotEmpty) {
      ids.addAll(MetricsDefinitions.guardianMetricIds);
    }
    if (request.astReport != null && request.astReport!.isNotEmpty) {
      ids.addAll(MetricsDefinitions.astMetricIds);
    }
    return ids;
  }

  Future<ProjectGraph> _resolveGraph(MetricsRequest request) async {
    if (request.projectGraph != null && request.projectGraph!.isNotEmpty) {
      return ProjectGraph.fromJson(request.projectGraph!);
    }
    final provider = _graphProvider;
    if (provider == null) {
      throw MetricsGraphException('Project graph was not provided');
    }
    final graph = await provider.load();
    if (graph == null) {
      throw MetricsGraphException('GraphProvider returned null graph');
    }
    return graph;
  }
}
