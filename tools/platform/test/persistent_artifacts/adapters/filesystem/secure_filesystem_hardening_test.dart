import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem hardening umbrella', () {
    test('end-to-end write manifest read delete quarantine flow', () async {
      final root = createTempSandbox('umbrella');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      final store = backend.contentStore as SecureFilesystemContentStore;
      final manifests = backend.manifestStore as SecureFilesystemManifestStore;
      final deleter =
          backend.quarantineProvider as SecureFilesystemQuarantineProvider;

      final handle = await store.writeContent(
        descriptor: descriptor(namespace: 'umb'),
        bytes: utf8Bytes('artifact'),
      );
      final m =
          manifest(manifestId: 'umb-m1', artifactId: 'umb-a1', versionId: 'v1');
      await manifests.saveManifest(m);
      final loaded = await manifests.loadManifest('umb-m1');
      expect(loaded, isNotNull);
      expect(await store.readContent(handle), utf8Bytes('artifact'));
      final quarantine = await deleter.deleteWithResult(handle: handle);
      expect(quarantine.outcome, SecureFilesystemBackendOutcome.succeeded);
    });
  });
}
