import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('SecureFilesystemQuarantineProvider', () {
    test('moves file to quarantine when enabled', () async {
      final root = createTempSandbox('quarantine-on');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(
        buildConfig(root, quarantineEnabled: true),
      );
      final store = backend.contentStore as SecureFilesystemContentStore;
      final deleter =
          backend.quarantineProvider as SecureFilesystemQuarantineProvider;

      final handle = await store.writeContent(
        descriptor: descriptor(namespace: 'q-ns'),
        bytes: utf8Bytes('payload'),
      );
      final result = await deleter.deleteWithResult(handle: handle);
      expect(result.outcome, SecureFilesystemBackendOutcome.succeeded);
      expect(result.quarantined, isTrue);
      expect(await store.readContent(handle), isNull);
    });

    test('physically deletes when quarantine disabled', () async {
      final root = createTempSandbox('quarantine-off');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(
        buildConfig(root, quarantineEnabled: false),
      );
      final store = backend.contentStore as SecureFilesystemContentStore;
      final deleter =
          backend.quarantineProvider as SecureFilesystemQuarantineProvider;

      final handle = await store.writeContent(
        descriptor: descriptor(namespace: 'q-ns'),
        bytes: utf8Bytes('payload'),
      );
      final result = await deleter.deleteWithResult(handle: handle);
      expect(result.outcome, SecureFilesystemBackendOutcome.succeeded);
      expect(result.quarantined, isFalse);
      expect(await store.readContent(handle), isNull);
    });
  });
}
