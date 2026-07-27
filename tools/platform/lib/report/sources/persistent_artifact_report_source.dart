import '../../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';
import '../../models/persistent_artifacts/persistent_artifact_enums.dart';
import '../report_input.dart';

class PersistentArtifactReportSource {
  const PersistentArtifactReportSource();

  PersistentArtifactReportInputData fromSnapshot(
    PersistentArtifactInfrastructureSnapshot snapshot,
  ) {
    return PersistentArtifactReportInputData(
      snapshotId: snapshot.identity?.persistentArtifactInfrastructureId ??
          snapshot.metadata['snapshotId'] ??
          'unknown',
      projectId: snapshot.projectId,
      releaseId: snapshot.releaseId ?? '',
      status: snapshot.status.wireName,
      subjectCount: snapshot.subjects.length,
      sourceCount: snapshot.sourceReferences.length,
      policyCount: snapshot.policyReferences.length,
      operationCount: snapshot.operationResults.length,
      limitations: const [
        'declarative-boundaries-only',
        'no-physical-storage-by-default',
      ],
      warnings: const [],
    );
  }

  PersistentArtifactReportInputData fromMap(Map<String, dynamic> json) {
    return fromSnapshot(
        PersistentArtifactInfrastructureSnapshot.fromJson(json));
  }
}
