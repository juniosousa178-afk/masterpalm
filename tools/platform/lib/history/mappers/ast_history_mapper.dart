import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../history_canonical_serializer.dart';

/// Maps AST report payload to [HistoryArtifact].
class AstHistoryMapper {
  const AstHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final canonical = {
      'meta': json['meta'] ?? {},
      'metrics': json['metrics'] ?? {},
    };
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(canonical),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.ast,
      artifactId: 'ast:$fingerprint',
      schemaVersion: 1,
      fingerprint: fingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: Map<String, dynamic>.from(json),
      ),
    );
  }
}
