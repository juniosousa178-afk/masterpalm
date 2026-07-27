import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem stress integration', () {
    for (var i = 0; i < 8; i++) {
      test('batch write/read $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final handles = <PersistentArtifactContentHandle>[];
        for (var j = 0; j < 25; j++) {
          final w = await stack.provider.writePhysicalContent(
            WritePhysicalContentRequest(
              backendId: 'fs-int',
              contentId: 'stress-$i-$j',
              bytes: [j],
            ),
          );
          handles.add(w.handle!);
        }
        for (final handle in handles) {
          final read = await stack.provider.readPhysicalContent(
            ReadPhysicalContentRequest(backendId: 'fs-int', handle: handle),
          );
          expect(
              read.status, PersistentArtifactPhysicalOperationStatus.succeeded);
        }
      });
    }
  });
}
