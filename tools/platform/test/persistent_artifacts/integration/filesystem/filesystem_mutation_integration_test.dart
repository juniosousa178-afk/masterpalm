import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem mutation integration', () {
    for (var i = 0; i < 8; i++) {
      test('quarantine removes availability $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final write = await stack.provider.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: 'fs-int',
            contentId: 'mut-$i',
            bytes: [1, i],
          ),
        );
        await stack.provider.quarantineContent(
          QuarantineContentRequest(backendId: 'fs-int', handle: write.handle!),
        );
        final exists = await stack.provider.contentExists(
          ContentExistsRequest(backendId: 'fs-int', handle: write.handle!),
        );
        expect(exists.exists, isFalse);
      });
    }
  });
}
