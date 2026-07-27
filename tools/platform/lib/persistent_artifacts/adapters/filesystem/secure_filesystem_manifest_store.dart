import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../interfaces/persistent_artifact_manifest_store.dart';
import '../../../models/persistent_artifacts/persistent_artifact_manifest.dart';
import '../../../models/persistent_artifacts/persistent_artifact_query.dart';
import 'secure_filesystem_backend_config.dart';
import 'secure_filesystem_backend_result.dart';
import 'secure_filesystem_location_resolver.dart';
import 'secure_filesystem_path_resolver.dart';

class SecureFilesystemManifestStore implements PersistentArtifactManifestStore {
  SecureFilesystemManifestStore({
    required SecureFilesystemBackendConfig config,
    required SecureFilesystemPathResolver pathResolver,
    required SecureFilesystemLocationResolver locationResolver,
  })  : _config = config,
        _pathResolver = pathResolver,
        _locationResolver = locationResolver;

  final SecureFilesystemBackendConfig _config;
  final SecureFilesystemPathResolver _pathResolver;
  final SecureFilesystemLocationResolver _locationResolver;

  @override
  Future<void> saveManifest(PersistentArtifactManifest manifest) async {
    final result = await saveManifestWithResult(manifest);
    if (result.outcome != SecureFilesystemBackendOutcome.succeeded) {
      throw FileSystemException(
        'secure filesystem manifest save rejected',
        result.locationReference,
      );
    }
  }

  Future<SecureFilesystemManifestSaveResult> saveManifestWithResult(
    PersistentArtifactManifest manifest,
  ) async {
    final namespace =
        _locationResolver.namespaceFromProject(manifest.subject.projectId);
    final file =
        _manifestFile(namespace, manifest.artifactId, manifest.versionId);
    await file.parent.create(recursive: true);
    final encoded = _encodeManifest(manifest);

    if (await file.exists()) {
      final existing = await file.readAsString();
      if (existing == encoded) {
        return SecureFilesystemManifestSaveResult(
          outcome: SecureFilesystemBackendOutcome.succeeded,
          manifestId: manifest.manifestId,
          idempotent: true,
          locationReference: _manifestLocationReference(
              namespace, manifest.artifactId, manifest.versionId),
        );
      }
      return SecureFilesystemManifestSaveResult(
        outcome: SecureFilesystemBackendOutcome.conflict,
        manifestId: manifest.manifestId,
        locationReference: _manifestLocationReference(
            namespace, manifest.artifactId, manifest.versionId),
        issues: const [
          SecureFilesystemBackendIssue(
            code: 'manifest-conflict',
            message: 'Existing manifest has different payload',
          ),
        ],
      );
    }

    if (_config.useAtomicWrites) {
      final tempDir =
          _pathResolver.resolveDirectory([_config.tempDirectoryName]);
      await tempDir.create(recursive: true);
      final temp = _pathResolver.resolveFile([
        _config.tempDirectoryName,
        '${manifest.manifestId}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ]);
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    } else {
      await file.writeAsString(encoded, flush: true);
    }
    return SecureFilesystemManifestSaveResult(
      outcome: SecureFilesystemBackendOutcome.succeeded,
      manifestId: manifest.manifestId,
      locationReference: _manifestLocationReference(
          namespace, manifest.artifactId, manifest.versionId),
    );
  }

  @override
  Future<PersistentArtifactManifest?> loadManifest(String manifestId) async {
    final result = await loadManifestWithResult(manifestId);
    return result.manifest;
  }

  Future<SecureFilesystemManifestLoadResult<PersistentArtifactManifest>>
      loadManifestWithResult(String manifestId) async {
    final file = await _findManifestFileByManifestId(manifestId);
    if (file == null || !await file.exists()) {
      return const SecureFilesystemManifestLoadResult(
        outcome: SecureFilesystemBackendOutcome.notFound,
      );
    }
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final manifest = PersistentArtifactManifest.fromJson(decoded);
    return SecureFilesystemManifestLoadResult(
      outcome: SecureFilesystemBackendOutcome.succeeded,
      manifest: manifest,
      locationReference: _pathResolver.publicLocationForRelativePath(
        p
            .relative(file.path, from: _pathResolver.rootDirectory.path)
            .replaceAll('\\', '/'),
      ),
    );
  }

  Future<PersistentArtifactManifest?> latest({
    required String artifactId,
    String? namespace,
  }) async {
    final all = await list(namespace: namespace);
    final matches = all.where((m) => m.artifactId == artifactId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.isEmpty ? null : matches.first;
  }

  Future<List<PersistentArtifactManifest>> query(
      PersistentArtifactQuery query) async {
    var values = await list();
    values = values.where((manifest) {
      if (query.projectId != null &&
          manifest.subject.projectId != query.projectId) {
        return false;
      }
      if (query.releaseId != null &&
          manifest.subject.releaseId != query.releaseId) {
        return false;
      }
      if (query.artifactId != null && manifest.artifactId != query.artifactId) {
        return false;
      }
      if (query.createdFrom != null &&
          manifest.createdAt.compareTo(query.createdFrom!) < 0) {
        return false;
      }
      if (query.createdUntil != null &&
          manifest.createdAt.compareTo(query.createdUntil!) > 0) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (query.offset != null && query.offset! > 0) {
      if (query.offset! >= values.length) return const [];
      values = values.sublist(query.offset!);
    }
    if (query.limit != null && query.limit! < values.length) {
      values = values.sublist(0, query.limit!);
    }
    return List.unmodifiable(values);
  }

  Future<List<PersistentArtifactManifest>> list({String? namespace}) async {
    final manifestRoot = namespace == null
        ? _pathResolver.resolveDirectory([_config.manifestDirectoryName])
        : _pathResolver
            .resolveDirectory([_config.manifestDirectoryName, namespace]);
    if (!await manifestRoot.exists()) {
      return const [];
    }
    final manifests = <PersistentArtifactManifest>[];
    await for (final entity
        in manifestRoot.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      final relative =
          p.relative(entity.path, from: _pathResolver.rootDirectory.path);
      _pathResolver
          .ensureWithinRoot(p.join(_pathResolver.rootDirectory.path, relative));
      final decoded =
          jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
      manifests.add(PersistentArtifactManifest.fromJson(decoded));
    }
    manifests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(manifests);
  }

  Future<void> invalidate(String manifestId) async {
    final file = await _findManifestFileByManifestId(manifestId);
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }

  File _manifestFile(String namespace, String artifactId, String versionId) {
    return _pathResolver.resolveFile([
      _config.manifestDirectoryName,
      namespace,
      artifactId,
      '$versionId.json',
    ]);
  }

  String _manifestLocationReference(
      String namespace, String artifactId, String versionId) {
    return _pathResolver.publicLocationForRelativePath(
      p
          .join(
            _config.manifestDirectoryName,
            namespace,
            artifactId,
            '$versionId.json',
          )
          .replaceAll('\\', '/'),
    );
  }

  Future<File?> _findManifestFileByManifestId(String manifestId) async {
    final all = await list();
    for (final manifest in all) {
      if (manifest.manifestId != manifestId) {
        continue;
      }
      final namespace =
          _locationResolver.namespaceFromProject(manifest.subject.projectId);
      return _manifestFile(namespace, manifest.artifactId, manifest.versionId);
    }
    return null;
  }

  String _encodeManifest(PersistentArtifactManifest manifest) {
    return const JsonEncoder.withIndent('  ').convert(manifest.toJson());
  }
}
