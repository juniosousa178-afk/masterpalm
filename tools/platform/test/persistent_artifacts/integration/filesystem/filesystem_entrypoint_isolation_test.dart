import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('filesystem entrypoint isolation', () {
    test('core entrypoint does not export filesystem adapters', () {
      final file = File('lib/masterpalm_platform.dart');
      final content = file.readAsStringSync();
      expect(
          content.contains('adapters/filesystem/secure_filesystem_'), isFalse);
      expect(content.contains('masterpalm_platform_filesystem'), isFalse);
    });

    test('filesystem entrypoint exports adapter surface', () {
      final file = File('lib/masterpalm_platform_filesystem.dart');
      final content = file.readAsStringSync();
      expect(
          content.contains('secure_filesystem_backend_factory.dart'), isTrue);
      expect(content.contains('registerSecureFilesystemBackend'), isTrue);
    });
  });
}
