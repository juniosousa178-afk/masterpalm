import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem hardening integration umbrella', () {
    for (var i = 0; i < 8; i++) {
      test('unsupported backend id returns unavailable $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final read = await stack.provider.readPhysicalContent(
          const ReadPhysicalContentRequest(
            backendId: 'missing',
            handle: InMemoryPersistentArtifactContentHandle(
              handleId: 'h',
              backendId: 'missing',
            ),
          ),
        );
        expect(
            read.status, PersistentArtifactPhysicalOperationStatus.unavailable);
      });
    }
  });
}
