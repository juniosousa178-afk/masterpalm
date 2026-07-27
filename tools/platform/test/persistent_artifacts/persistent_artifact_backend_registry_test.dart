import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/persistent_artifacts/interfaces/persistent_artifact_interfaces.dart';
import 'package:test/test.dart';

class _NoopStore implements PersistentArtifactContentStore {
  @override
  Future<void> deleteContent(PersistentArtifactContentHandle handle) async {}

  @override
  Future<List<int>?> readContent(
          PersistentArtifactContentHandle handle) async =>
      const [1];

  @override
  Future<PersistentArtifactContentHandle> writeContent({
    required PersistentArtifactContentDescriptor descriptor,
    required List<int> bytes,
  }) async {
    return const InMemoryPersistentArtifactContentHandle(
      handleId: 'h1',
      backendId: 'b1',
    );
  }
}

void main() {
  group('PersistentArtifactBackendRegistry', () {
    test('registra e resolve backend', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.registerContentStore('mem', _NoopStore());
      expect(registry.resolveContentStore('mem'), isNotNull);
    });

    test('lista backends ordenados', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.registerContentStore('z', _NoopStore());
      registry.registerContentStore('a', _NoopStore());
      expect(registry.backends(), ['a', 'z']);
    });

    test('freeze bloqueia novos registros', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.freeze();
      expect(
        () => registry.registerContentStore('x', _NoopStore()),
        throwsA(isA<PersistentArtifactRegistryFrozenException>()),
      );
    });

    test('resolve inexistente retorna nulo', () {
      final registry = PersistentArtifactBackendRegistry();
      expect(registry.resolveContentStore('nao'), isNull);
    });

    test('isFrozen refletido', () {
      final registry = PersistentArtifactBackendRegistry();
      expect(registry.isFrozen, isFalse);
      registry.freeze();
      expect(registry.isFrozen, isTrue);
    });

    test('sobrescreve backend antes de freeze', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.registerContentStore('mem', _NoopStore());
      registry.registerContentStore('mem', _NoopStore());
      expect(registry.backends().length, 1);
    });

    test('aceita multiplos backends', () {
      final registry = PersistentArtifactBackendRegistry();
      for (var i = 0; i < 3; i++) {
        registry.registerContentStore('b$i', _NoopStore());
      }
      expect(registry.backends().length, 3);
    });

    test('resolve depois de freeze funciona', () {
      final registry = PersistentArtifactBackendRegistry();
      registry.registerContentStore('mem', _NoopStore());
      registry.freeze();
      expect(registry.resolveContentStore('mem'), isNotNull);
    });
  });
}
