import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

class _NoopStore implements PersistentArtifactContentStore {
  @override
  Future<void> deleteContent(PersistentArtifactContentHandle handle) async {}

  @override
  Future<List<int>?> readContent(
          PersistentArtifactContentHandle handle) async =>
      const [1, 2, 3];

  @override
  Future<PersistentArtifactContentHandle> writeContent({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  }) async =>
      const InMemoryPersistentArtifactContentHandle(
        handleId: 'h',
        backendId: 'b',
      );
}

void main() {
  group('Persistent Artifact backend registry audit', () {
    test('register and resolve content store', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.registerContentStore('memory', _NoopStore());
      expect(registry.backends(), contains('memory'));
      expect(registry.resolveContentStore('memory'), isNotNull);
    });

    test('backend list is sorted', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.registerContentStore('z', _NoopStore());
      registry.registerContentStore('a', _NoopStore());
      expect(registry.backends(), ['a', 'z']);
    });

    test('frozen backend registry rejects writes', () {
      final registry = PersistentArtifactBackendRegistry()..freeze();
      expect(
        () => registry.registerContentStore('memory', _NoopStore()),
        throwsA(isA<PersistentArtifactRegistryFrozenException>()),
      );
    });
  });
}
