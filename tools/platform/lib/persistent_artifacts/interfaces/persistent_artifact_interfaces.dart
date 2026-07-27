import '../../models/persistent_artifacts/persistent_artifact_content_descriptor.dart';
import '../../models/persistent_artifacts/persistent_artifact_manifest.dart';
import '../../models/persistent_artifacts/persistent_artifact_operational_models.dart';
import '../../models/persistent_artifacts/persistent_artifact_query.dart';
import '../../models/persistent_artifacts/persistent_artifact_subject.dart';
import '../../models/persistent_artifacts/persistent_artifact_infrastructure_snapshot.dart';

abstract interface class PersistentArtifactContentHandle {
  String get handleId;
  String get backendId;
}

abstract interface class PersistentArtifactContentStore {
  Future<PersistentArtifactContentHandle> writeContent({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  });

  Future<List<int>?> readContent(PersistentArtifactContentHandle handle);

  Future<void> deleteContent(PersistentArtifactContentHandle handle);
}

abstract interface class PersistentArtifactManifestStore {
  Future<void> saveManifest(PersistentArtifactManifest manifest);
  Future<PersistentArtifactManifest?> loadManifest(String manifestId);
}

abstract interface class PersistentArtifactLocationResolver {
  Future<List<String>> resolveLocations({
    required PersistentArtifactSubject subject,
    required bool useLatest,
  });
}

abstract interface class PersistentArtifactContentReader {
  Future<List<int>?> read(PersistentArtifactContentHandle handle);
}

abstract interface class PersistentArtifactContentWriter {
  Future<PersistentArtifactContentHandle> write({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  });
}

abstract interface class PersistentArtifactPhysicalDeletionProvider {
  Future<void> delete({
    required PersistentArtifactContentHandle handle,
    required bool force,
  });
}

abstract interface class PersistentArtifactSnapshotStore {
  Future<void> save(PersistentArtifactInfrastructureSnapshot snapshot);
  Future<PersistentArtifactInfrastructureSnapshot?> load(String snapshotId);
  Future<bool> exists(String snapshotId);
  Future<PersistentArtifactInfrastructureSnapshot?> latest({
    required String projectId,
    String? releaseId,
  });
  Future<List<PersistentArtifactInfrastructureSnapshot>> query(
    PersistentArtifactQuery query,
  );
  Future<void> invalidate(String snapshotId);
  Future<void> clear();
  Future<int> count();
}

class InMemoryPersistentArtifactContentHandle
    implements PersistentArtifactContentHandle {
  const InMemoryPersistentArtifactContentHandle({
    required this.handleId,
    required this.backendId,
  });

  @override
  final String handleId;

  @override
  final String backendId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InMemoryPersistentArtifactContentHandle &&
          handleId == other.handleId &&
          backendId == other.backendId;

  @override
  int get hashCode => Object.hash(handleId, backendId);
}

class PersistentArtifactContentUnavailableException implements Exception {
  const PersistentArtifactContentUnavailableException(this.message);
  final String message;

  @override
  String toString() =>
      'PersistentArtifactContentUnavailableException: $message';
}
