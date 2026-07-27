import 'dart:convert';

import '../../models/dashboard/dashboard_snapshot.dart';
import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../history_canonical_serializer.dart';

/// Maps [DashboardSnapshot] to [HistoryArtifact].
class DashboardHistoryMapper {
  const DashboardHistoryMapper({HistoryCanonicalSerializer? serializer})
      : _serializer = serializer ?? const HistoryCanonicalSerializer();

  final HistoryCanonicalSerializer _serializer;

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = DashboardSnapshot.fromJson(json);
    final comparable = snapshot.toComparableJson();
    final fingerprint = _serializer.fingerprintFromString(
      jsonEncode(comparable),
    );
    return HistoryArtifact(
      artifactType: HistoryArtifactType.dashboard,
      artifactId: snapshot.metadata.dashboardSnapshotId,
      schemaVersion: snapshot.metadata.dashboardSchemaVersion,
      canonicalizationVersion:
          snapshot.metadata.dashboardCanonicalizationVersion,
      calculationVersion: snapshot.metadata.dashboardCalculationVersion,
      fingerprint: fingerprint,
      sourceSnapshotId: snapshot.metadata.queryFingerprint,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }
}
