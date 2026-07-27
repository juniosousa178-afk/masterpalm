import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem portability integration', () {
    for (var i = 0; i < 8; i++) {
      test('location resolution remains backend-neutral $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final result = await stack.provider.resolvePhysicalLocation(
          ResolvePhysicalLocationRequest(
            backendId: 'fs-int',
            subject: PersistentArtifactSubject(
              subjectId: 's-$i',
              artifactType: PersistentArtifactType.manifest,
              projectId: 'proj-$i',
              sourceModule: 'module',
              sourceId: 'id-$i',
              sourceFingerprint: 'fp-$i',
            ),
          ),
        );
        expect(
            result.status, PersistentArtifactPhysicalOperationStatus.succeeded);
      });
    }
  });
}
