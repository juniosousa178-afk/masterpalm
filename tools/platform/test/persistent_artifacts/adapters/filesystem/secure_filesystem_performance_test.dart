import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem performance', () {
    test('write/read loops complete within broad threshold', () async {
      final root = createTempSandbox('perf');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      final store = backend.contentStore as SecureFilesystemContentStore;

      final sw = Stopwatch()..start();
      for (var i = 0; i < 400; i++) {
        final handle = await store.writeContent(
          descriptor: descriptor(namespace: 'perf', contentId: 'perf-$i'),
          bytes: utf8Bytes('perf-payload-$i'),
        );
        final read = await store.readContent(handle);
        expect(read, isNotNull);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(30000));
    });
  });
}
