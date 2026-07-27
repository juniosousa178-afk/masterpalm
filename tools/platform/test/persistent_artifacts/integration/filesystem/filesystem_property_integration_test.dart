import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem property integration', () {
    for (var i = 0; i < 8; i++) {
      test('same payload keeps deterministic digest $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final req = WritePhysicalContentRequest(
          backendId: 'fs-int',
          contentId: 'prop-$i',
          bytes: const [8, 9, 10],
        );
        final a = await stack.provider.writePhysicalContent(req);
        final b = await stack.provider.writePhysicalContent(req);
        expect(a.digest, b.digest);
      });
    }
  });
}
