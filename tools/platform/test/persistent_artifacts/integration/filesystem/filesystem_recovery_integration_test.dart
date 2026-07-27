import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem recovery integration', () {
    for (var i = 0; i < 8; i++) {
      test('inspects recovery surfaces $i', () async {
        final stack = createFilesystemStack(enableRecoveryInspector: true);
        addTearDown(() => cleanupFilesystemStack(stack));
        final interrupted =
            await stack.provider.inspectInterruptedOperations('fs-int');
        final orphan =
            await stack.provider.inspectOrphanTemporaryObjects('fs-int');
        expect(
          interrupted.status,
          PersistentArtifactPhysicalOperationStatus.succeeded,
        );
        expect(
            orphan.status, PersistentArtifactPhysicalOperationStatus.succeeded);
      });
    }
  });
}
