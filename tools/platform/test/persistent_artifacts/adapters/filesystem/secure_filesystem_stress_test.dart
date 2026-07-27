import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem stress', () {
    test('stores 5000 objects and 1000 manifests', () async {
      final root = createTempSandbox('stress');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(
        buildConfig(root, maxBytes: 1024 * 1024 * 2),
      );
      final store = backend.contentStore as SecureFilesystemContentStore;
      final manifestStore =
          backend.manifestStore as SecureFilesystemManifestStore;

      for (var i = 0; i < 5000; i++) {
        final result = await store.writeWithResult(
          descriptor: descriptor(namespace: 'stress', contentId: 'c-$i'),
          bytes: utf8Bytes('payload-$i'),
        );
        expect(result.outcome, SecureFilesystemBackendOutcome.succeeded);
      }

      for (var i = 0; i < 1000; i++) {
        await manifestStore.saveManifest(
          manifest(
            manifestId: 'm-$i',
            artifactId: 'artifact-${i % 20}',
            versionId: 'v-$i',
            createdAt: '2026-01-${(i % 28) + 1}T00:00:00Z',
          ),
        );
      }

      final listed = await manifestStore.list();
      expect(listed.length, 1000);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
