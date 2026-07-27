import 'dart:io';

import '../../interfaces/persistent_artifact_physical_deletion_provider.dart';
import '../../interfaces/persistent_artifact_content_handle.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_backend_result.dart';
import 'secure_filesystem_content_handle.dart';
import 'secure_filesystem_path_resolver.dart';

class SecureFilesystemQuarantineProvider
    implements PersistentArtifactPhysicalDeletionProvider {
  SecureFilesystemQuarantineProvider({
    required SecureFilesystemBackendConfig config,
    required SecureFilesystemPathResolver pathResolver,
  })  : _config = config,
        _pathResolver = pathResolver;

  final SecureFilesystemBackendConfig _config;
  final SecureFilesystemPathResolver _pathResolver;

  @override
  Future<void> delete({
    required PersistentArtifactContentHandle handle,
    required bool force,
  }) async {
    final _ = force;
    final result = await deleteWithResult(handle: handle);
    if (result.outcome == SecureFilesystemBackendOutcome.notFound) {
      return;
    }
    if (result.outcome != SecureFilesystemBackendOutcome.succeeded) {
      throw const FileSystemException('secure filesystem deletion failed');
    }
  }

  Future<SecureFilesystemQuarantineResult> deleteWithResult({
    required PersistentArtifactContentHandle handle,
  }) async {
    final secureHandle = _requireHandleType(handle);
    final target =
        _pathResolver.resolveFile(secureHandle.relativePath.split('/'));
    if (!await target.exists()) {
      return const SecureFilesystemQuarantineResult(
        outcome: SecureFilesystemBackendOutcome.notFound,
        quarantined: false,
      );
    }
    if (!_config.quarantineEnabled) {
      await target.delete();
      return const SecureFilesystemQuarantineResult(
        outcome: SecureFilesystemBackendOutcome.succeeded,
        quarantined: false,
      );
    }
    final quarantine = _pathResolver.resolveFile([
      _config.quarantineDirectoryName,
      secureHandle.namespace,
      '${DateTime.now().millisecondsSinceEpoch}-${secureHandle.digest}',
    ]);
    await quarantine.parent.create(recursive: true);
    await target.rename(quarantine.path);
    return SecureFilesystemQuarantineResult(
      outcome: SecureFilesystemBackendOutcome.succeeded,
      quarantined: true,
      locationReference: _pathResolver.publicLocationForRelativePath(
        '${_config.quarantineDirectoryName}/${secureHandle.namespace}',
      ),
    );
  }

  SecureFilesystemPersistentArtifactContentHandle _requireHandleType(
    PersistentArtifactContentHandle handle,
  ) {
    if (handle is! SecureFilesystemPersistentArtifactContentHandle) {
      throw const FormatException('Unsupported content handle type');
    }
    if (handle.backendId != _config.backendId) {
      throw const FormatException('Content handle backend mismatch');
    }
    return handle;
  }
}
