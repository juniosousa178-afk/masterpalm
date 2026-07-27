import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem security integration', () {
    for (var i = 0; i < 8; i++) {
      test('rejects oversize payload $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final provider = stack.provider;
        final bytes = List<int>.filled(1024 * 1024 + 32 + i, 7);
        final result = await provider.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: 'fs-int',
            contentId: 'oversize-$i',
            bytes: bytes,
            namespace: 'sec',
          ),
        );
        expect(
          result.status,
          anyOf(
            PersistentArtifactPhysicalOperationStatus.exceededLimit,
            PersistentArtifactPhysicalOperationStatus.rejected,
          ),
        );
      });
    }
  });
}
