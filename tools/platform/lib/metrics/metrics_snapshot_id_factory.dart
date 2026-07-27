import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/graph/project_graph.dart';
import '../models/metrics/metrics_metadata.dart';
import 'metrics_canonical_serializer.dart';

/// Deterministic snapshot identity factory.
class MetricsSnapshotIdFactory {
  const MetricsSnapshotIdFactory({
    MetricsCanonicalSerializer? serializer,
  }) : _serializer = serializer ?? const MetricsCanonicalSerializer();

  final MetricsCanonicalSerializer _serializer;

  String graphFingerprint(ProjectGraph graph) {
    final canonical = _serializer.canonicalizeGraph(graph);
    final bytes = utf8.encode(canonical);
    return sha256.convert(bytes).toString();
  }

  String create({
    required String projectId,
    required String sourceGraphFingerprint,
    int calculationVersion = MetricsMetadata.currentCalculationVersion,
  }) {
    return 'metrics:$projectId:$sourceGraphFingerprint:$calculationVersion';
  }
}
