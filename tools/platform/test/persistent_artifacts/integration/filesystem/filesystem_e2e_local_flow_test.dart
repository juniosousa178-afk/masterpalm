import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem e2e local flow', () {
    for (var i = 0; i < 8; i++) {
      test('local flow $i write read quarantine', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final provider = stack.provider;
        final write = await provider.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: 'fs-int',
            contentId: 'flow-$i',
            bytes: [1, 2, i],
            namespace: 'flow',
          ),
        );
        final read = await provider.readPhysicalContent(
          ReadPhysicalContentRequest(
              backendId: 'fs-int', handle: write.handle!),
        );
        expect(read.bytes, [1, 2, i]);
        final quarantine = await provider.quarantineContent(
          QuarantineContentRequest(backendId: 'fs-int', handle: write.handle!),
        );
        expect(
          quarantine.status,
          anyOf(
            PersistentArtifactPhysicalOperationStatus.succeeded,
            PersistentArtifactPhysicalOperationStatus.notFound,
          ),
        );
      });
    }
  });
}
