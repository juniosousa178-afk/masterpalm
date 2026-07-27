import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/metrics/metrics_snapshot.dart';
import '../history_canonical_serializer.dart';

/// Maps [MetricsSnapshot] to [HistoryArtifact].
class MetricsHistoryMapper {
  const MetricsHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = MetricsSnapshot.fromJson(json);
    final comparable = snapshot.toComparableJson();
    final metrics = List<Map<String, dynamic>>.from(
      comparable['metrics'] as List<dynamic>,
    )..sort(
        (a, b) => ((a['definition'] as Map)['id'] as String)
            .compareTo((b['definition'] as Map)['id'] as String),
      );
    comparable['metrics'] = metrics;
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.metrics,
      artifactId: snapshot.metadata.snapshotId,
      schemaVersion: snapshot.metadata.metricsSchemaVersion,
      canonicalizationVersion: snapshot.metadata.metricsCanonicalizationVersion,
      calculationVersion: snapshot.metadata.metricsCalculationVersion,
      fingerprint: fingerprint,
      sourceSnapshotId: snapshot.metadata.sourceSnapshotId,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }
}
