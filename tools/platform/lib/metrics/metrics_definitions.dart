import '../models/metrics/metric_category.dart';
import '../models/metrics/metric_definition.dart';
import '../models/metrics/metric_source.dart';
import '../models/metrics/metric_unit.dart';
import '../models/metrics/metric_value_type.dart';

/// Central catalog of metric definitions.
class MetricsDefinitions {
  const MetricsDefinitions._();

  static const calculationVersion = 1;

  static MetricDefinition def({
    required String id,
    required String name,
    required MetricCategory category,
    required MetricValueType valueType,
    required MetricUnit unit,
    required MetricSource source,
    required String description,
  }) {
    return MetricDefinition(
      id: id,
      name: name,
      category: category,
      valueType: valueType,
      unit: unit,
      source: source,
      description: description,
      calculationVersion: calculationVersion,
    );
  }

  static final Map<String, MetricDefinition> all = {
    for (final d in _definitions) d.id: d,
  };

  static final Set<String> defaultMetricIds = {
    for (final d in _definitions)
      if (d.source == MetricSource.graph) d.id,
  };

  static final Set<String> guardianMetricIds = {
    for (final d in _definitions)
      if (d.source == MetricSource.guardian) d.id,
  };

  static final Set<String> astMetricIds = {
    for (final d in _definitions)
      if (d.source == MetricSource.ast) d.id,
  };

  static final List<MetricDefinition> _definitions = [
    def(
      id: 'graph.node.count',
      name: 'Graph node count',
      category: MetricCategory.graphStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Total number of nodes in the project graph.',
    ),
    def(
      id: 'graph.edge.count',
      name: 'Graph edge count',
      category: MetricCategory.graphStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Total number of deduplicated directed edges.',
    ),
    def(
      id: 'graph.node.count.by_type',
      name: 'Node count by type',
      category: MetricCategory.nodeDistribution,
      valueType: MetricValueType.distribution,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Distribution of node counts grouped by node type.',
    ),
    def(
      id: 'graph.edge.count.by_type',
      name: 'Edge count by type',
      category: MetricCategory.edgeDistribution,
      valueType: MetricValueType.distribution,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Distribution of edge counts grouped by edge type.',
    ),
    def(
      id: 'graph.degree.fan_in',
      name: 'Fan-in by node',
      category: MetricCategory.dependency,
      valueType: MetricValueType.distribution,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Incoming edge count per node in the deduplicated graph.',
    ),
    def(
      id: 'graph.degree.fan_out',
      name: 'Fan-out by node',
      category: MetricCategory.dependency,
      valueType: MetricValueType.distribution,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Outgoing edge count per node in the deduplicated graph.',
    ),
    def(
      id: 'graph.degree.fan_in.average',
      name: 'Average fan-in',
      category: MetricCategory.dependency,
      valueType: MetricValueType.decimal,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Average incoming edge count across all nodes.',
    ),
    def(
      id: 'graph.degree.fan_out.average',
      name: 'Average fan-out',
      category: MetricCategory.dependency,
      valueType: MetricValueType.decimal,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Average outgoing edge count across all nodes.',
    ),
    def(
      id: 'graph.degree.fan_in.max',
      name: 'Maximum fan-in',
      category: MetricCategory.dependency,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Maximum incoming edge count for any node.',
    ),
    def(
      id: 'graph.degree.fan_out.max',
      name: 'Maximum fan-out',
      category: MetricCategory.dependency,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Maximum outgoing edge count for any node.',
    ),
    def(
      id: 'graph.component.isolated_count',
      name: 'Isolated node count',
      category: MetricCategory.connectivity,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Nodes with zero incident edges.',
    ),
    def(
      id: 'graph.component.isolated.by_type',
      name: 'Isolated nodes by type',
      category: MetricCategory.connectivity,
      valueType: MetricValueType.distribution,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Distribution of isolated nodes grouped by node type.',
    ),
    def(
      id: 'graph.density',
      name: 'Directed graph density',
      category: MetricCategory.connectivity,
      valueType: MetricValueType.decimal,
      unit: MetricUnit.ratio,
      source: MetricSource.graph,
      description:
          'edgeCount / (nodeCount * (nodeCount - 1)) for directed graph without self-loops.',
    ),
    def(
      id: 'graph.component.weak.count',
      name: 'Weakly connected component count',
      category: MetricCategory.connectivity,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description:
          'Number of weakly connected components (edges treated as undirected).',
    ),
    def(
      id: 'graph.component.weak.largest_size',
      name: 'Largest weak component size',
      category: MetricCategory.connectivity,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Size of the largest weakly connected component.',
    ),
    def(
      id: 'graph.cycle.count',
      name: 'Structural cycle count',
      category: MetricCategory.cycle,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description:
          'Number of strongly connected components with more than one node.',
    ),
    def(
      id: 'graph.cycle.node_count',
      name: 'Nodes participating in cycles',
      category: MetricCategory.cycle,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Nodes belonging to cyclic strongly connected components.',
    ),
    def(
      id: 'graph.cycle.largest_component_size',
      name: 'Largest cyclic component size',
      category: MetricCategory.cycle,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Size of the largest strongly connected cyclic component.',
    ),
    def(
      id: 'graph.depth.bounded_max',
      name: 'Bounded maximum depth',
      category: MetricCategory.connectivity,
      valueType: MetricValueType.integer,
      unit: MetricUnit.depth,
      source: MetricSource.graph,
      description:
          'Maximum directed depth discovered within the configured depth limit.',
    ),
    def(
      id: 'storage.firestore.collection_count',
      name: 'Firestore collection node count',
      category: MetricCategory.storageAccess,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of firestoreCollection nodes in the graph.',
    ),
    def(
      id: 'storage.firestore.read_edge_count',
      name: 'Firestore read edge count',
      category: MetricCategory.storageAccess,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of readsFrom edges targeting Firestore collections.',
    ),
    def(
      id: 'storage.firestore.write_edge_count',
      name: 'Firestore write edge count',
      category: MetricCategory.storageAccess,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of writesTo edges targeting Firestore collections.',
    ),
    def(
      id: 'storage.hive.box_count',
      name: 'Hive box node count',
      category: MetricCategory.storageAccess,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of hiveBox nodes present in the graph.',
    ),
    def(
      id: 'storage.hive.access_edge_count',
      name: 'Hive access edge count',
      category: MetricCategory.storageAccess,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of accesses edges targeting Hive boxes.',
    ),
    def(
      id: 'callable.method.count',
      name: 'Method node count',
      category: MetricCategory.callableStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of method nodes in the graph.',
    ),
    def(
      id: 'callable.constructor.count',
      name: 'Constructor node count',
      category: MetricCategory.callableStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of constructor nodes in the graph.',
    ),
    def(
      id: 'callable.function.count',
      name: 'Function node count',
      category: MetricCategory.callableStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of top-level function nodes in the graph.',
    ),
    def(
      id: 'callable.call_edge_count',
      name: 'Call edge count',
      category: MetricCategory.callableStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description: 'Number of calls edges in the graph.',
    ),
    def(
      id: 'callable.uncalled_count',
      name: 'Uncalled callable count',
      category: MetricCategory.callableStructure,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.graph,
      description:
          'Callable nodes without incoming calls edges within the known graph.',
    ),
    def(
      id: 'guardian.violation.count',
      name: 'Guardian violation count',
      category: MetricCategory.importedGuardian,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.guardian,
      description: 'Imported violation count from Guardian analysis.',
    ),
    def(
      id: 'guardian.violation.count.by_severity',
      name: 'Guardian violations by severity',
      category: MetricCategory.importedGuardian,
      valueType: MetricValueType.distribution,
      unit: MetricUnit.count,
      source: MetricSource.guardian,
      description: 'Imported violation distribution by severity.',
    ),
    def(
      id: 'guardian.required_test.count',
      name: 'Guardian required test count',
      category: MetricCategory.importedGuardian,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.guardian,
      description: 'Imported required test count from Guardian analysis.',
    ),
    def(
      id: 'guardian.decision',
      name: 'Guardian decision',
      category: MetricCategory.importedGuardian,
      valueType: MetricValueType.text,
      unit: MetricUnit.text,
      source: MetricSource.guardian,
      description: 'Imported Guardian decision value.',
    ),
    def(
      id: 'guardian.risk.level',
      name: 'Guardian risk level',
      category: MetricCategory.importedGuardian,
      valueType: MetricValueType.text,
      unit: MetricUnit.text,
      source: MetricSource.guardian,
      description: 'Imported Guardian overall risk level.',
    ),
    def(
      id: 'ast.file.count',
      name: 'AST file count',
      category: MetricCategory.importedAst,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.ast,
      description: 'Imported files_analyzed count from AST report.',
    ),
    def(
      id: 'ast.class.count',
      name: 'AST class count',
      category: MetricCategory.importedAst,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.ast,
      description: 'Imported total_classes from AST report metrics.',
    ),
    def(
      id: 'ast.method.count',
      name: 'AST method count',
      category: MetricCategory.importedAst,
      valueType: MetricValueType.integer,
      unit: MetricUnit.count,
      source: MetricSource.ast,
      description: 'Imported total_methods from AST report metrics.',
    ),
  ];
}
