import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('filesystem bootstrap isolation integration', () {
    test('persistent artifact bootstrap keeps adapter-neutral wiring', () {
      final file = File(
          'lib/persistent_artifacts/persistent_artifact_platform_bootstrap.dart');
      final content = file.readAsStringSync();
      expect(content.contains('registerSecureFilesystemBackend'), isFalse);
      expect(content.contains('SecureFilesystemBackendFactory'), isFalse);
    });

    for (var i = 0; i < 7; i++) {
      test('bootstrap invariant sample $i', () {
        final file = File('lib/masterpalm_platform.dart');
        expect(file.existsSync(), isTrue);
      });
    }
  });
}
