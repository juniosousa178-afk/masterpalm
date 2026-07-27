import '../../models/graph/graph_edge_type.dart';
import '../../models/graph/graph_node_type.dart';
import '../../models/metrics/metric_availability.dart';
import '../../models/metrics/metric_distribution.dart';
import '../../models/metrics/metric_record.dart';
import '../../models/metrics/metric_source.dart';
import '../../models/metrics/metric_value.dart';
import '../algorithms/bounded_graph_depth.dart';
import '../algorithms/strongly_connected_components.dart';
import '../metric_calculator.dart';
import '../metrics_definitions.dart';
import '../metrics_math.dart';

/// Calculates graph-derived structural metrics.
class GraphMetricsCalculator implements MetricCalculator {
  const GraphMetricsCalculator();

  @override
  Set<String> get metricIds => MetricsDefinitions.defaultMetricIds;

  @override
  Set<MetricSource> get requiredSources => {MetricSource.graph};

  @override
  List<MetricRecord> calculate(MetricsCalculationContext context) {
    final ctx = context.graphContext;
    final records = <MetricRecord>[];
    final defs = MetricsDefinitions.all;

    void addInt(String id, int value) {
      if (!context.wants(id)) return;
      records.add(MetricRecord(
        definition: defs[id]!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(value),
      ));
    }

    void addDecimal(String id, double value) {
      if (!context.wants(id)) return;
      records.add(MetricRecord(
        definition: defs[id]!,
        availability: MetricAvailability.available,
        value: DecimalMetricValue(MetricsMath.normalizeDecimal(value)),
      ));
    }

    void addDistribution(String id, Map<String, double> entries) {
      if (!context.wants(id)) return;
      records.add(MetricRecord(
        definition: defs[id]!,
        availability: MetricAvailability.available,
        value: DistributionMetricValue(MetricDistribution(entries)),
      ));
    }

    final nodeCount = ctx.sortedNodes.length;
    final edgeCount = ctx.sortedEdges.length;

    addInt('graph.node.count', nodeCount);
    addInt('graph.edge.count', edgeCount);

    if (context.wants('graph.node.count.by_type')) {
      final byType = <String, double>{};
      for (final node in ctx.sortedNodes) {
        final key = node.type.wireName;
        byType[key] = (byType[key] ?? 0) + 1;
      }
      addDistribution('graph.node.count.by_type', byType);
    }

    if (context.wants('graph.edge.count.by_type')) {
      final byType = <String, double>{};
      for (final edge in ctx.sortedEdges) {
        final key = edge.type.wireName;
        byType[key] = (byType[key] ?? 0) + 1;
      }
      addDistribution('graph.edge.count.by_type', byType);
    }

    final fanInDist = <String, double>{
      for (final id in ctx.sortedNodeIds) id: (ctx.fanIn[id] ?? 0).toDouble(),
    };
    final fanOutDist = <String, double>{
      for (final id in ctx.sortedNodeIds) id: (ctx.fanOut[id] ?? 0).toDouble(),
    };

    addDistribution('graph.degree.fan_in', fanInDist);
    addDistribution('graph.degree.fan_out', fanOutDist);

    if (nodeCount > 0) {
      final totalFanIn = fanInDist.values.fold<double>(0, (sum, v) => sum + v);
      final totalFanOut =
          fanOutDist.values.fold<double>(0, (sum, v) => sum + v);
      addDecimal('graph.degree.fan_in.average', totalFanIn / nodeCount);
      addDecimal('graph.degree.fan_out.average', totalFanOut / nodeCount);
    } else {
      addDecimal('graph.degree.fan_in.average', 0);
      addDecimal('graph.degree.fan_out.average', 0);
    }

    addInt(
      'graph.degree.fan_in.max',
      fanInDist.values.isEmpty
          ? 0
          : fanInDist.values
              .map((v) => v.toInt())
              .reduce((a, b) => a > b ? a : b),
    );
    addInt(
      'graph.degree.fan_out.max',
      fanOutDist.values.isEmpty
          ? 0
          : fanOutDist.values
              .map((v) => v.toInt())
              .reduce((a, b) => a > b ? a : b),
    );

    final isolated = ctx.sortedNodeIds
        .where((id) => (ctx.fanIn[id] ?? 0) + (ctx.fanOut[id] ?? 0) == 0)
        .toList();
    addInt('graph.component.isolated_count', isolated.length);

    if (context.wants('graph.component.isolated.by_type')) {
      final isolatedByType = <String, double>{};
      for (final node in ctx.sortedNodes) {
        if (!isolated.contains(node.id)) continue;
        final key = node.type.wireName;
        isolatedByType[key] = (isolatedByType[key] ?? 0) + 1;
      }
      addDistribution('graph.component.isolated.by_type', isolatedByType);
    }

    addDecimal(
      'graph.density',
      MetricsMath.directedDensity(nodeCount, edgeCount),
    );

    final weakComponents = weaklyConnectedComponents(ctx.graph);
    addInt('graph.component.weak.count', weakComponents.length);
    addInt(
      'graph.component.weak.largest_size',
      weakComponents.isEmpty
          ? 0
          : weakComponents.map((c) => c.length).reduce((a, b) => a > b ? a : b),
    );

    final sccs = stronglyConnectedComponents(
      ctx.directedAdjacency,
      ctx.sortedNodeIds,
    );
    final cyclic = sccs.where((c) => c.length > 1).toList();
    addInt('graph.cycle.count', cyclic.length);
    addInt(
      'graph.cycle.node_count',
      cyclic.fold<int>(0, (sum, c) => sum + c.length),
    );
    addInt(
      'graph.cycle.largest_component_size',
      cyclic.isEmpty
          ? 0
          : cyclic.map((c) => c.length).reduce((a, b) => a > b ? a : b),
    );

    if (context.wants('graph.depth.bounded_max')) {
      final depth = boundedGraphDepthMax(ctx.graph, context.depthLimit);
      records.add(MetricRecord(
        definition: defs['graph.depth.bounded_max']!,
        availability: MetricAvailability.available,
        value: IntegerMetricValue(depth.maxDepth),
        message: depth.limitReached
            ? 'Depth limit ${context.depthLimit} may prevent broader conclusions'
            : null,
      ));
    }

    addInt(
      'storage.firestore.collection_count',
      ctx.sortedNodes
          .where((n) => n.type == GraphNodeType.firestoreCollection)
          .length,
    );
    addInt(
      'storage.firestore.read_edge_count',
      ctx.sortedEdges.where((e) => e.type == GraphEdgeType.readsFrom).length,
    );
    addInt(
      'storage.firestore.write_edge_count',
      ctx.sortedEdges.where((e) => e.type == GraphEdgeType.writesTo).length,
    );

    final hiveNodes =
        ctx.sortedNodes.where((n) => n.type == GraphNodeType.hiveBox).length;
    addInt('storage.hive.box_count', hiveNodes);
    addInt(
      'storage.hive.access_edge_count',
      ctx.sortedEdges.where((e) => e.type == GraphEdgeType.accesses).length,
    );

    addInt(
      'callable.method.count',
      ctx.sortedNodes.where((n) => n.type == GraphNodeType.method).length,
    );
    addInt(
      'callable.constructor.count',
      ctx.sortedNodes.where((n) => n.type == GraphNodeType.constructor).length,
    );
    addInt(
      'callable.function.count',
      ctx.sortedNodes.where((n) => n.type == GraphNodeType.function).length,
    );
    addInt(
      'callable.call_edge_count',
      ctx.sortedEdges.where((e) => e.type == GraphEdgeType.calls).length,
    );

    if (context.wants('callable.uncalled_count')) {
      final callableTypes = {
        GraphNodeType.method,
        GraphNodeType.constructor,
        GraphNodeType.function,
      };
      var uncalled = 0;
      for (final node in ctx.sortedNodes) {
        if (!callableTypes.contains(node.type)) continue;
        final incomingCalls = ctx.sortedEdges.where(
          (e) => e.targetId == node.id && e.type == GraphEdgeType.calls,
        );
        if (incomingCalls.isEmpty) uncalled++;
      }
      addInt('callable.uncalled_count', uncalled);
    }

    return records;
  }
}
