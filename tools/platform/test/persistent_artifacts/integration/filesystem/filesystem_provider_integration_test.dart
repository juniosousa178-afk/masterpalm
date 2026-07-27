import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/models/persistent_artifacts/persistent_artifact_manifest.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

PersistentArtifactManifest _manifest(String id) {
  return PersistentArtifactManifest(
    manifestId: id,
    artifactId: 'artifact-$id',
    versionId: 'v1',
    subject: const PersistentArtifactSubject(
      subjectId: 'subject',
      artifactType: PersistentArtifactType.manifest,
      projectId: 'proj',
      sourceModule: 'module',
      sourceId: 'sid',
      sourceFingerprint: 'sfp',
    ),
    contentDescriptor: const PersistentArtifactContentDescriptor(
      contentId: 'content',
      mediaType: 'application/json',
      format: PersistentArtifactFormat.json,
      encoding: PersistentArtifactEncoding.utf8,
      compression: PersistentArtifactCompression.none,
      contentFingerprint: 'fp',
    ),
    createdAt: '2026-01-01T00:00:00Z',
  );
}

void main() {
  group('filesystem provider integration', () {
    for (var i = 0; i < 30; i++) {
      test('case $i physical operations baseline', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final provider = stack.provider;
        final write = await provider.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: 'fs-int',
            contentId: 'content-$i',
            bytes: [i, i + 1, i + 2],
            namespace: 'n$i',
          ),
        );
        expect(
            write.status, PersistentArtifactPhysicalOperationStatus.succeeded);
        final exists = await provider.contentExists(
          ContentExistsRequest(backendId: 'fs-int', handle: write.handle!),
        );
        expect(exists.exists, isTrue);

        final saveManifest = await provider.savePhysicalManifest(
          SavePhysicalManifestRequest(
            backendId: 'fs-int',
            manifest: _manifest('m-$i'),
          ),
        );
        expect(
          saveManifest.status,
          PersistentArtifactPhysicalOperationStatus.succeeded,
        );
        final loaded = await provider.loadPhysicalManifest(
          LoadPhysicalManifestRequest(backendId: 'fs-int', manifestId: 'm-$i'),
        );
        expect(loaded.manifest?.manifestId, 'm-$i');
      });
    }
  });
}
