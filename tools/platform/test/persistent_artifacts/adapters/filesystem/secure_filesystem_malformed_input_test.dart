import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem malformed input', () {
    late Directory root;
    late SecureFilesystemContentStore store;

    setUp(() {
      root = createTempSandbox('malformed');
      final backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      store = backend.contentStore as SecureFilesystemContentStore;
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    for (final value in const [
      '..',
      '../',
      '..\\',
      '%2e%2e',
      '%2E%2E',
      '/absolute',
      r'\absolute',
      r'\\unc\path',
      r'D:\drive',
      '~/.profile',
      'a\tb',
      'a\nb',
      'a\rb',
      'a\u007Fb',
    ]) {
      test('reject namespace malformed: "$value"', () async {
        final result = await store.writeWithResult(
          descriptor: descriptor(namespace: value),
          bytes: utf8Bytes('x'),
        );
        expect(result.outcome, isNot(SecureFilesystemBackendOutcome.succeeded));
      });
    }
  });
}
