import 'dart:async';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem concurrency integration', () {
    for (var i = 0; i < 8; i++) {
      test('parallel writes $i', () async {
        final stack = createFilesystemStack();
        addTearDown(() => cleanupFilesystemStack(stack));
        final provider = stack.provider;
        final futures = <Future<WritePhysicalContentResult>>[];
        for (var j = 0; j < 10; j++) {
          futures.add(
            provider.writePhysicalContent(
              WritePhysicalContentRequest(
                backendId: 'fs-int',
                contentId: 'c-$i-$j',
                bytes: [j, i],
              ),
            ),
          );
        }
        final results = await Future.wait(futures);
        expect(
          results.where((r) =>
              r.status == PersistentArtifactPhysicalOperationStatus.succeeded),
          hasLength(10),
        );
      });
    }
  });
}
