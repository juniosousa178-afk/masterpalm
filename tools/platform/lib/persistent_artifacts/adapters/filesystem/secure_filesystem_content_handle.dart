import '../../interfaces/persistent_artifact_content_handle.dart';

class SecureFilesystemPersistentArtifactContentHandle
    implements PersistentArtifactContentHandle {
  const SecureFilesystemPersistentArtifactContentHandle({
    required this.handleId,
    required this.backendId,
    required this.namespace,
    required this.digest,
    required this.relativePath,
  });

  @override
  final String handleId;

  @override
  final String backendId;

  final String namespace;
  final String digest;
  final String relativePath;
}
