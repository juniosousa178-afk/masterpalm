import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/secure_filesystem_test_helpers.dart';

void main() {
  group('Secure filesystem contract', () {
    test('factory wires all required contracts', () {
      final root = createTempSandbox('contract');
      addTearDown(() => root.deleteSync(recursive: true));
      final backend = SecureFilesystemBackendFactory.create(buildConfig(root));
      expect(backend.contentStore, isA<PersistentArtifactContentStore>());
      expect(backend.manifestStore, isA<PersistentArtifactManifestStore>());
      expect(
        backend.locationResolver,
        isA<PersistentArtifactLocationResolver>(),
      );
      expect(backend.contentReader, isA<PersistentArtifactContentReader>());
      expect(backend.contentWriter, isA<PersistentArtifactContentWriter>());
      expect(
        backend.quarantineProvider,
        isA<PersistentArtifactPhysicalDeletionProvider>(),
      );
    });
  });
}
