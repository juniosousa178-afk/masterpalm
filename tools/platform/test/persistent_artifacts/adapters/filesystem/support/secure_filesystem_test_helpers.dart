import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_manifest.dart';

Directory createTempSandbox([String suffix = 'secure-fs']) {
  final root = Directory.systemTemp.createTempSync('mp-$suffix-');
  return root;
}

SecureFilesystemBackendConfig buildConfig(
  Directory root, {
  String backendId = 'secure-fs',
  int maxBytes = 1024 * 1024,
  bool quarantineEnabled = true,
  bool enableRecoveryInspector = true,
  bool allowUserHomeRoot = true,
}) {
  return SecureFilesystemBackendConfig(
    backendId: backendId,
    rootDirectory: root.path,
    namespacePrefix: 'test-ns',
    maximumContentSizeBytes: maxBytes,
    quarantineEnabled: quarantineEnabled,
    enableRecoveryInspector: enableRecoveryInspector,
    allowUserHomeRoot: allowUserHomeRoot,
  );
}

PersistentArtifactContentDescriptor descriptor({
  String contentId = 'content-1',
  String? namespace,
  String? canonicalDigest,
}) {
  return PersistentArtifactContentDescriptor(
    contentId: contentId,
    mediaType: 'application/octet-stream',
    format: PersistentArtifactFormat.binary,
    encoding: PersistentArtifactEncoding.none,
    compression: PersistentArtifactCompression.none,
    canonicalDigest: canonicalDigest,
    contentFingerprint: 'fp-$contentId',
    metadata: namespace == null ? const {} : {'namespace': namespace},
  );
}

PersistentArtifactSubject subject({
  String subjectId = 'subject-1',
  String projectId = 'proj-1',
  String? releaseId = 'rel-1',
}) {
  return PersistentArtifactSubject(
    subjectId: subjectId,
    artifactType: PersistentArtifactType.manifest,
    projectId: projectId,
    releaseId: releaseId,
    sourceModule: 'module',
    sourceId: 'src-id',
    sourceFingerprint: 'src-fp',
    contentType: 'application/json',
  );
}

PersistentArtifactManifest manifest({
  String manifestId = 'manifest-1',
  String artifactId = 'artifact-1',
  String versionId = 'v1',
  String createdAt = '2026-01-01T00:00:00Z',
  PersistentArtifactSubject? customSubject,
}) {
  return PersistentArtifactManifest(
    manifestId: manifestId,
    artifactId: artifactId,
    versionId: versionId,
    subject: customSubject ?? subject(),
    contentDescriptor: descriptor(contentId: 'content-$versionId'),
    createdAt: createdAt,
    metadata: const {'test': 'true'},
  );
}

List<int> utf8Bytes(String value) => utf8.encode(value);
