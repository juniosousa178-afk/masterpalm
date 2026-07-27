import 'dart:io';

import '../../backend/persistent_artifact_backend_registration.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_path_resolver.dart';

class SecureFilesystemRecoveryInspector
    implements PersistentArtifactRecoveryInspector {
  SecureFilesystemRecoveryInspector({
    required SecureFilesystemBackendConfig config,
    required SecureFilesystemPathResolver pathResolver,
  })  : _config = config,
        _pathResolver = pathResolver;

  final SecureFilesystemBackendConfig _config;
  final SecureFilesystemPathResolver _pathResolver;

  Future<List<String>> listQuarantinedReferences() async {
    if (!_config.enableRecoveryInspector) {
      return const [];
    }
    final dir =
        _pathResolver.resolveDirectory([_config.quarantineDirectoryName]);
    if (!await dir.exists()) {
      return const [];
    }
    final refs = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relative = entity.path
            .replaceFirst('${_pathResolver.rootDirectory.path}\\', '');
        refs.add(_pathResolver
            .publicLocationForRelativePath(relative.replaceAll('\\', '/')));
      }
    }
    refs.sort();
    return refs;
  }

  Future<List<String>> listOrphanTemporaryObjects() async {
    if (!_config.enableRecoveryInspector) {
      return const [];
    }
    final tempDir = _pathResolver.resolveDirectory([_config.tempDirectoryName]);
    if (!await tempDir.exists()) {
      return const [];
    }
    final refs = <String>[];
    await for (final entity
        in tempDir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        refs.add(entity.path);
      }
    }
    refs.sort();
    return refs;
  }

  Future<List<String>> inspectInterruptedOperations() async {
    return listOrphanTemporaryObjects();
  }

  Future<bool> recoverTemporaryObject(String reference) async {
    if (!_config.enableRecoveryInspector) {
      return false;
    }
    final file = File(reference);
    if (!await file.exists()) {
      return false;
    }
    return true;
  }

  Future<bool> discardTemporaryObject(String reference) async {
    if (!_config.enableRecoveryInspector) {
      return false;
    }
    final file = File(reference);
    if (!await file.exists()) {
      return false;
    }
    await file.delete();
    return true;
  }
}
