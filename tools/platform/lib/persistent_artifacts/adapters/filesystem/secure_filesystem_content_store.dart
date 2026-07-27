import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../interfaces/persistent_artifact_content_reader.dart';
import '../../interfaces/persistent_artifact_content_store.dart';
import '../../interfaces/persistent_artifact_content_writer.dart';
import '../../interfaces/persistent_artifact_content_handle.dart';
import '../../../models/persistent_artifacts/persistent_artifact_content_descriptor.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_backend_result.dart';
import 'secure_filesystem_content_handle.dart';
import 'secure_filesystem_path_resolver.dart';

class SecureFilesystemContentStore
    implements
        PersistentArtifactContentStore,
        PersistentArtifactContentReader,
        PersistentArtifactContentWriter {
  SecureFilesystemContentStore({
    required SecureFilesystemBackendConfig config,
    required SecureFilesystemPathResolver pathResolver,
  })  : _config = config,
        _pathResolver = pathResolver;

  final SecureFilesystemBackendConfig _config;
  final SecureFilesystemPathResolver _pathResolver;

  @override
  Future<SecureFilesystemPersistentArtifactContentHandle> writeContent({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  }) async {
    final result = await writeWithResult(descriptor: descriptor, bytes: bytes);
    if (result.outcome != SecureFilesystemBackendOutcome.succeeded) {
      throw FileSystemException(
        'secure filesystem content write rejected',
        result.locationReference,
      );
    }
    return _toHandle(
      backendId: _config.backendId,
      namespace: _namespaceFor(descriptor),
      digest: result.digest,
    );
  }

  @override
  Future<SecureFilesystemPersistentArtifactContentHandle> write({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  }) {
    return writeContent(descriptor: descriptor, bytes: bytes);
  }

  Future<SecureFilesystemWriteResult> writeWithResult({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  }) async {
    if (bytes.length > _config.maximumContentSizeBytes) {
      return SecureFilesystemWriteResult(
        outcome: SecureFilesystemBackendOutcome.exceededLimit,
        digest: '',
        sizeBytes: bytes.length,
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'content-size-limit',
            message: 'Content size exceeds configured limit',
          ),
        ],
      );
    }
    final digest = sha256.convert(bytes).toString();
    final expectedDigest = descriptor.canonicalDigest;
    if (expectedDigest != null &&
        expectedDigest.isNotEmpty &&
        expectedDigest != digest) {
      return SecureFilesystemWriteResult(
        outcome: SecureFilesystemBackendOutcome.conflict,
        digest: digest,
        sizeBytes: bytes.length,
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'digest-mismatch',
            message: 'Descriptor digest does not match payload digest',
          ),
        ],
      );
    }

    final namespace = _namespaceFor(descriptor);
    final prefix = digest.substring(0, 2);
    final relativePath = p.url.join(
      _config.contentDirectoryName,
      namespace,
      prefix,
      digest,
    );
    late final File target;
    try {
      target = _pathResolver.resolveFile(relativePath.split('/'));
      await target.parent.create(recursive: true);
    } on FormatException {
      return SecureFilesystemWriteResult(
        outcome: SecureFilesystemBackendOutcome.rejected,
        digest: digest,
        sizeBytes: bytes.length,
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'unsafe-path',
            message: 'Path validation rejected write',
          ),
        ],
      );
    } on FileSystemException {
      return SecureFilesystemWriteResult(
        outcome: SecureFilesystemBackendOutcome.rejected,
        digest: digest,
        sizeBytes: bytes.length,
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'unsafe-path',
            message: 'Path validation rejected write',
          ),
        ],
      );
    }

    if (await target.exists()) {
      final existingBytes = await target.readAsBytes();
      final existingDigest = sha256.convert(existingBytes).toString();
      if (existingDigest == digest) {
        return SecureFilesystemWriteResult(
          outcome: SecureFilesystemBackendOutcome.succeeded,
          digest: digest,
          sizeBytes: bytes.length,
          locationReference:
              _pathResolver.publicLocationForRelativePath(relativePath),
          idempotent: true,
        );
      }
      return SecureFilesystemWriteResult(
        outcome: SecureFilesystemBackendOutcome.conflict,
        digest: digest,
        sizeBytes: bytes.length,
        locationReference:
            _pathResolver.publicLocationForRelativePath(relativePath),
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'digest-conflict',
            message: 'Existing object has different digest',
          ),
        ],
      );
    }

    try {
      if (_config.useAtomicWrites) {
        await _atomicWrite(target: target, bytes: bytes, digest: digest);
      } else {
        await target.writeAsBytes(bytes, flush: true);
      }
      if (_config.verifyDigestAfterWrite) {
        final persisted = await target.readAsBytes();
        if (sha256.convert(persisted).toString() != digest) {
          try {
            await target.delete();
          } on FileSystemException {
            // Best-effort cleanup only.
          }
          return SecureFilesystemWriteResult(
            outcome: SecureFilesystemBackendOutcome.ioError,
            digest: digest,
            sizeBytes: bytes.length,
            issues: const [
              SecureFilesystemBackendIssue(
                code: 'post-write-verification-failed',
                message: 'Persisted bytes digest does not match',
              ),
            ],
          );
        }
      }
    } on FileSystemException {
      if (await target.exists()) {
        final persisted = await target.readAsBytes();
        if (sha256.convert(persisted).toString() == digest) {
          return SecureFilesystemWriteResult(
            outcome: SecureFilesystemBackendOutcome.succeeded,
            digest: digest,
            sizeBytes: bytes.length,
            locationReference:
                _pathResolver.publicLocationForRelativePath(relativePath),
            idempotent: true,
          );
        }
      }
      return SecureFilesystemWriteResult(
        outcome: SecureFilesystemBackendOutcome.ioError,
        digest: digest,
        sizeBytes: bytes.length,
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'io-write-failure',
            message: 'Unable to persist content bytes',
          ),
        ],
      );
    }

    return SecureFilesystemWriteResult(
      outcome: SecureFilesystemBackendOutcome.succeeded,
      digest: digest,
      sizeBytes: bytes.length,
      locationReference:
          _pathResolver.publicLocationForRelativePath(relativePath),
    );
  }

  @override
  Future<List<int>?> readContent(PersistentArtifactContentHandle handle) async {
    final result = await readWithResult(handle);
    return result.bytes;
  }

  @override
  Future<List<int>?> read(PersistentArtifactContentHandle handle) {
    return readContent(handle);
  }

  Future<SecureFilesystemReadResult> readWithResult(
    PersistentArtifactContentHandle handle,
  ) async {
    final secureHandle = _requireHandleType(handle);
    final file =
        _pathResolver.resolveFile(secureHandle.relativePath.split('/'));
    if (!await file.exists()) {
      return const SecureFilesystemReadResult(
        outcome: SecureFilesystemBackendOutcome.notFound,
      );
    }
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    return SecureFilesystemReadResult(
      outcome: SecureFilesystemBackendOutcome.succeeded,
      bytes: bytes,
      digest: digest,
    );
  }

  @override
  Future<void> deleteContent(PersistentArtifactContentHandle handle) async {
    final secureHandle = _requireHandleType(handle);
    final file =
        _pathResolver.resolveFile(secureHandle.relativePath.split('/'));
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<SecureFilesystemExistsResult> exists(
      PersistentArtifactContentHandle handle) async {
    final secureHandle = _requireHandleType(handle);
    final file =
        _pathResolver.resolveFile(secureHandle.relativePath.split('/'));
    return SecureFilesystemExistsResult(
      outcome: SecureFilesystemBackendOutcome.succeeded,
      exists: await file.exists(),
    );
  }

  Future<void> _atomicWrite({
    required File target,
    required List<int> bytes,
    required String digest,
  }) async {
    final tempDir = _pathResolver.resolveDirectory([_config.tempDirectoryName]);
    await tempDir.create(recursive: true);
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final tempName = '$digest.$nonce.tmp';
    final tempFile =
        _pathResolver.resolveFile([_config.tempDirectoryName, tempName]);
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsBytes(bytes, flush: true);
    try {
      await tempFile.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // Best-effort cleanup only.
        }
        return;
      }
      rethrow;
    }
  }

  SecureFilesystemPersistentArtifactContentHandle _toHandle({
    required String backendId,
    required String namespace,
    required String digest,
  }) {
    final prefix = digest.substring(0, 2);
    final relativePath = p.url.join(
      _config.contentDirectoryName,
      namespace,
      prefix,
      digest,
    );
    return SecureFilesystemPersistentArtifactContentHandle(
      handleId: '$backendId:$namespace:$digest',
      backendId: backendId,
      namespace: namespace,
      digest: digest,
      relativePath: relativePath.replaceAll('\\', '/'),
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

  String _namespaceFor(PersistentArtifactContentDescriptor descriptor) {
    final preferred = descriptor.metadata['namespace'];
    if (preferred != null && preferred.trim().isNotEmpty) {
      return preferred.trim();
    }
    final prefix = _config.namespacePrefix?.trim();
    if (prefix == null || prefix.isEmpty) {
      return 'default';
    }
    return prefix;
  }
}
