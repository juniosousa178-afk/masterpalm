import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem concurrency', () {
    test('concurrent writes complete without collisions', () async {
      final root = createTempSandbox('concurrency');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      final store = backend.contentStore as SecureFilesystemContentStore;

      final futures = List.generate(
        20,
        (i) => store.writeWithResult(
          descriptor: descriptor(namespace: 'cc-$i', contentId: 'c-$i'),
          bytes: utf8Bytes('payload-$i'),
        ),
      );
      final results = await Future.wait(futures);
      expect(
        results
            .where((r) => r.outcome == SecureFilesystemBackendOutcome.succeeded)
            .length,
        20,
      );
      expect(results.map((r) => r.digest).toSet().length, 20);
    });
  });
}
