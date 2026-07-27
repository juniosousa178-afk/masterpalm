import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/filesystem_integration_helpers.dart';

void main() {
  group('filesystem backend registration', () {
    test('registers backend and exposes capabilities', () {
      final stack = createFilesystemStack();
      addTearDown(() => cleanupFilesystemStack(stack));

      expect(stack.registry.contains('fs-int'), isTrue);
      final matches = stack.registry.queryCapabilities(
        PersistentArtifactBackendCapability.contentWrite,
      );
      expect(matches.any((it) => it.descriptor.backendId == 'fs-int'), isTrue);
    });

    test('idempotent registration with same config', () {
      final stack = createFilesystemStack();
      addTearDown(() => cleanupFilesystemStack(stack));
      final handle = SecureFilesystemBackendFactory.registerInto(
        stack.registry,
        stack.config,
      );
      expect(handle.descriptor.backendId, 'fs-int');
      expect(stack.registry.backends(), ['fs-int']);
    });

    test('blocks non-production-eligible backend in production context', () {
      final rootStack = createFilesystemStack();
      addTearDown(() => cleanupFilesystemStack(rootStack));
      final productionRegistry = PersistentArtifactBackendRegistry(
        environmentContext:
            PersistentArtifactBackendEnvironmentContext.production,
      );
      expect(
        () => SecureFilesystemBackendFactory.registerInto(
          productionRegistry,
          rootStack.config,
          environmentContext:
              PersistentArtifactBackendEnvironmentContext.production,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
