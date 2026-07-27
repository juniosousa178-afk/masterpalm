import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem security', () {
    late Directory root;
    late SecureFilesystemArtifactBackend backend;
    late SecureFilesystemContentStore store;

    setUp(() {
      root = createTempSandbox('security');
      backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      store = backend.contentStore as SecureFilesystemContentStore;
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    for (final namespace in const [
      '..',
      '../a',
      r'..\a',
      '%2e%2e',
      r'\\server\share',
      r'C:\x',
      '/x',
      '~',
      'a\nb',
    ]) {
      test('blocks dangerous namespace "$namespace"', () async {
        final d = descriptor(namespace: namespace);
        final result = await store.writeWithResult(
          descriptor: d,
          bytes: utf8Bytes('payload'),
        );
        expect(result.outcome, isNot(SecureFilesystemBackendOutcome.succeeded));
      });
    }

    test('no absolute path leak in location reference', () async {
      final result = await store.writeWithResult(
        descriptor: descriptor(namespace: 'safe'),
        bytes: utf8Bytes('payload'),
      );
      expect(result.outcome, SecureFilesystemBackendOutcome.succeeded);
      expect(result.locationReference, isNot(contains(root.path)));
      expect(result.locationReference, contains('secure-fs://'));
    });

    test('follows root confinement for writes', () async {
      final result = await store.writeWithResult(
        descriptor: descriptor(namespace: 'safe'),
        bytes: utf8Bytes('x'),
      );
      expect(result.outcome, SecureFilesystemBackendOutcome.succeeded);
      final contentDir =
          Directory('${root.path}${Platform.pathSeparator}content');
      expect(contentDir.existsSync(), isTrue);
    });

    test('fails closed when parent path is symlink', () async {
      final contentRoot =
          Directory('${root.path}${Platform.pathSeparator}content');
      contentRoot.createSync();
      final link = Link(
        '${contentRoot.path}${Platform.pathSeparator}test-ns',
      );
      try {
        link.createSync(root.path);
      } on FileSystemException {
        // Some CI/Windows profiles do not allow symlink creation.
        return;
      }
      final result =
          await (backend.contentStore as SecureFilesystemContentStore)
              .writeWithResult(
        descriptor: descriptor(namespace: 'test-ns'),
        bytes: utf8Bytes('payload'),
      );
      expect(result.outcome, isNot(SecureFilesystemBackendOutcome.succeeded));
    });
  });
}
