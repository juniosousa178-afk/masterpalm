import 'package:path/path.dart' as p;

import '../../interfaces/persistent_artifact_location_resolver.dart';
import '../../../models/persistent_artifacts/persistent_artifact_subject.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_path_resolver.dart';

class SecureFilesystemLocationResolver
    implements PersistentArtifactLocationResolver {
  SecureFilesystemLocationResolver({
    required SecureFilesystemBackendConfig config,
    required SecureFilesystemPathResolver pathResolver,
  })  : _config = config,
        _pathResolver = pathResolver;

  final SecureFilesystemBackendConfig _config;
  final SecureFilesystemPathResolver _pathResolver;

  @override
  Future<List<String>> resolveLocations({
    required PersistentArtifactSubject subject,
    required bool useLatest,
  }) async {
    final namespace = _namespaceFor(subject.projectId);
    final stableRef = resolveLocationReference(
      namespace: namespace,
      objectKey: p.join(
        'subjects',
        subject.subjectId,
        useLatest ? 'latest' : (subject.releaseId ?? 'no-release'),
      ),
    );
    return <String>[stableRef];
  }

  String resolveLocationReference({
    required String namespace,
    required String objectKey,
  }) {
    final safeNamespace = namespace.trim();
    final safeKey = objectKey.trim().replaceAll('\\', '/');
    if (safeNamespace.isEmpty || safeKey.isEmpty) {
      throw ArgumentError('namespace and objectKey are required');
    }
    return _pathResolver.publicLocationForRelativePath(
      p.url.join(
        _config.contentDirectoryName,
        safeNamespace,
        safeKey,
      ),
    );
  }

  String namespaceFromProject(String projectId) => _namespaceFor(projectId);

  String _namespaceFor(String projectId) {
    final prefix = _config.namespacePrefix?.trim();
    if (prefix == null || prefix.isEmpty) {
      return projectId;
    }
    return '$prefix-$projectId';
  }
}
