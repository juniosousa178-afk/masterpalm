import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem performance integration', () {
    for (var i = 0; i < 8; i++) {
      test('micro workload stays under broad threshold $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final sw = Stopwatch()..start();
        for (var j = 0; j < 20; j++) {
          await stack.provider.writePhysicalContent(
            WritePhysicalContentRequest(
              backendId: 'fs-int',
              contentId: 'perf-$i-$j',
              bytes: [i, j],
            ),
          );
        }
        sw.stop();
        expect(sw.elapsedMilliseconds < 5000, isTrue);
      });
    }
  });
}
