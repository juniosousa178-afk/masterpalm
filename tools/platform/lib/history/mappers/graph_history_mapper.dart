import '../../models/graph/project_graph.dart';
import '../../models/history/history_metadata.dart';
import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../metrics/metrics_canonical_serializer.dart';
import '../history_canonical_serializer.dart';

/// Maps [ProjectGraph] to [HistoryArtifact].
class GraphHistoryMapper {
  const GraphHistoryMapper({
    MetricsCanonicalSerializer? metricsSerializer,
    HistoryCanonicalSerializer? historySerializer,
  })  : _metricsSerializer =
            metricsSerializer ?? const MetricsCanonicalSerializer(),
        _historySerializer =
            historySerializer ?? const HistoryCanonicalSerializer();

  final MetricsCanonicalSerializer _metricsSerializer;
  final HistoryCanonicalSerializer _historySerializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final graph = ProjectGraph.fromJson(json);
    final canonical = _metricsSerializer.canonicalizeGraph(graph);
    final fingerprint = _historySerializer.fingerprintFromString(canonical);
    return HistoryArtifact(
      artifactType: HistoryArtifactType.graph,
      artifactId: 'graph:$fingerprint',
      schemaVersion: graph.metadata.graphSchemaVersion,
      canonicalizationVersion: HistoryMetadata.currentCanonicalizationVersion,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: graph.toJson(),
      ),
    );
  }
}
