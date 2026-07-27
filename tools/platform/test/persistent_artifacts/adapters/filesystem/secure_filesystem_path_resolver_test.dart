import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('SecureFilesystemPathResolver', () {
    late Directory root;
    late SecureFilesystemPathResolver resolver;

    setUp(() {
      root = createTempSandbox('resolver');
      resolver = SecureFilesystemPathResolver(config: buildConfig(root));
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('resolves normal file inside root', () {
      final file = resolver.resolveFile(['content', 'ns', 'ab', 'digest']);
      expect(file.path.contains(root.path), isTrue);
    });

    for (final segment in const [
      '..',
      '../x',
      r'..\x',
      '%2e%2e',
      '/abs',
      r'\abs',
      '~/home',
      r'\\server\share',
      r'C:\temp',
      'abc\x00def',
    ]) {
      test('rejects unsafe segment "$segment"', () {
        expect(
          () => resolver.resolveFile(['content', segment]),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test('rejects symlink leaf', () {
      final link = Link('${root.path}${Platform.pathSeparator}bad-link');
      link.createSync(root.path);
      expect(
        () => resolver.resolveFile(['bad-link']),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
