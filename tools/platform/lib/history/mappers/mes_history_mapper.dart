import 'dart:convert';

import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/mes/mes_snapshot.dart';
import '../history_canonical_serializer.dart';

/// Maps [MESSnapshot] to [HistoryArtifact].
class MESHistoryMapper {
  const MESHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = MESSnapshot.fromJson(json);
    final comparable = snapshot.toComparableJson();
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.mes,
      artifactId: snapshot.metadata.mesSnapshotId,
      schemaVersion: snapshot.metadata.mesSchemaVersion,
      canonicalizationVersion: snapshot.metadata.mesCanonicalizationVersion,
      calculationVersion: snapshot.metadata.mesCalculationVersion,
      fingerprint: fingerprint,
      sourceSnapshotId: snapshot.metadata.sourceEngineeringScoreSnapshotId,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }
}
