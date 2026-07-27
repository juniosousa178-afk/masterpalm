import '../../models/history/history_artifact.dart';
import '../../models/history/history_artifact_payload.dart';
import '../../models/history/history_artifact_type.dart';
import '../../models/history/history_change_type.dart';
import '../../models/history/history_diff.dart';
import '../../models/persistent_artifacts/persistent_artifact_enums.dart';
import '../../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';

class PersistentArtifactHistoryMapper {
  const PersistentArtifactHistoryMapper();

  HistoryArtifact fromMap(Map<String, dynamic> json) {
    final snapshot = PersistentArtifactInfrastructureSnapshot.fromJson(json);
    final artifactId = snapshot.identity?.persistentArtifactInfrastructureId ??
        snapshot.metadata['snapshotId'] ??
        'persistent-artifacts:unknown';
    return HistoryArtifact(
      artifactType: HistoryArtifactType.persistentArtifacts,
      artifactId: artifactId,
      schemaVersion: 1,
      canonicalizationVersion: 1,
      fingerprint: snapshot.metadata['fingerprint'] ?? artifactId,
      payload: HistoryArtifactPayload(
        encoding: HistoryArtifactPayload.jsonEncoding,
        data: snapshot.toJson(),
      ),
    );
  }

  List<HistoryChange> compare(
    PersistentArtifactInfrastructureSnapshot? from,
    PersistentArtifactInfrastructureSnapshot? to,
  ) {
    if (from == null || to == null) return const [];
    final changes = <HistoryChange>[];
    if (from.status != to.status) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'persistentArtifacts.status',
          previousValue: from.status.wireName,
          currentValue: to.status.wireName,
        ),
      );
    }
    if (from.subjects.length != to.subjects.length) {
      changes.add(
        HistoryChange(
          changeType: HistoryChangeType.artifactChanged,
          category: HistoryChangeCategory.artifact,
          subjectId: 'persistentArtifacts.subjectCount',
          previousValue: from.subjects.length.toString(),
          currentValue: to.subjects.length.toString(),
        ),
      );
    }
    return changes;
  }
}
