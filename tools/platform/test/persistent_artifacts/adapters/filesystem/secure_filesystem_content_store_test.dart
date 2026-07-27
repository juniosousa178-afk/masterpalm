import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('SecureFilesystemContentStore', () {
    late Directory root;
    late SecureFilesystemArtifactBackend backend;
    late SecureFilesystemContentStore store;

    setUp(() {
      root = createTempSandbox('content-store');
      backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      store = backend.contentStore as SecureFilesystemContentStore;
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('writes and reads roundtrip', () async {
      final handle = await store.writeContent(
        descriptor: descriptor(namespace: 'ns-a'),
        bytes: utf8Bytes('abc'),
      );
      final read = await store.readContent(handle);
      expect(read, utf8Bytes('abc'));
    });

    test('deletes content', () async {
      final handle = await store.writeContent(
        descriptor: descriptor(namespace: 'ns-del'),
        bytes: utf8Bytes('abc'),
      );
      await store.deleteContent(handle);
      expect(await store.readContent(handle), isNull);
    });

    test('enforces maximum size', () async {
      final smallRoot = createTempSandbox('content-small');
      addTearDown(() => smallRoot.deleteSync(recursive: true));
      final strict = SecureFilesystemBackendFactory.create(
        buildConfig(smallRoot, maxBytes: 4),
      ).contentStore as SecureFilesystemContentStore;
      final result = await strict.writeWithResult(
        descriptor: descriptor(namespace: 'ns'),
        bytes: utf8Bytes('12345'),
      );
      expect(result.outcome, SecureFilesystemBackendOutcome.exceededLimit);
    });

    test('rejects canonical digest mismatch', () async {
      final result = await store.writeWithResult(
        descriptor: descriptor(
          namespace: 'ns',
          canonicalDigest: sha256.convert(utf8Bytes('other')).toString(),
        ),
        bytes: utf8Bytes('abc'),
      );
      expect(result.outcome, SecureFilesystemBackendOutcome.conflict);
    });

    test('idempotent when same digest exists', () async {
      final one = await store.writeWithResult(
        descriptor: descriptor(namespace: 'ns'),
        bytes: utf8Bytes('abc'),
      );
      final two = await store.writeWithResult(
        descriptor: descriptor(namespace: 'ns'),
        bytes: utf8Bytes('abc'),
      );
      expect(one.outcome, SecureFilesystemBackendOutcome.succeeded);
      expect(two.outcome, SecureFilesystemBackendOutcome.succeeded);
      expect(two.idempotent, isTrue);
    });

    for (var i = 0; i < 35; i++) {
      test('writes unique payload case ${i + 1}', () async {
        final payload = 'payload-$i';
        final result = await store.writeWithResult(
          descriptor: descriptor(namespace: 'ns$i', contentId: 'content-$i'),
          bytes: utf8Bytes(payload),
        );
        expect(result.outcome, SecureFilesystemBackendOutcome.succeeded);
        final handle = await store.writeContent(
          descriptor: descriptor(namespace: 'ns$i', contentId: 'content-$i-2'),
          bytes: utf8Bytes(payload),
        );
        final read = await store.readWithResult(handle);
        expect(read.digest, sha256.convert(utf8Bytes(payload)).toString());
      });
    }
  });
}
