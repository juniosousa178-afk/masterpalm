import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

void main() {
  group('Secure filesystem bootstrap isolation', () {
    test('backend registry remains empty by default', () {
      final registry = PersistentArtifactBackendRegistry();
      expect(registry.backends(), isEmpty);
    });

    test('platform bootstrap file does not auto-register filesystem adapter',
        () {
      final file = File(
        'lib/persistent_artifacts/persistent_artifact_platform_bootstrap.dart',
      );
      final content = file.readAsStringSync();
      expect(content.contains('SecureFilesystemBackendFactory'), isFalse);
      expect(content.contains('secure-filesystem-reference'), isFalse);
    });
  });
}
