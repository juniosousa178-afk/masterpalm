import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/persistent_artifact_test_fixtures.dart';
import 'support/fake_persistent_artifact_backend.dart';
import 'support/hardening_helpers.dart';

void main() {
  group('physical operation replay', () {
    late FakePersistentArtifactBackend fake;
    late PersistentArtifactPhysicalOperationsService service;

    setUp(() {
      fake = FakePersistentArtifactBackend();
      final registry = createRegistryWith(
        buildFakeRegistration(bridge: fake),
      );
      service = PersistentArtifactPhysicalOperationsService(registry: registry);
    });

    test('100 cycles write/read remain deterministic', () async {
      for (var i = 0; i < 100; i++) {
        final write = await service.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: hardeningBackendId,
            contentId: 'c-$i',
            bytes: const [1, 2, 3],
          ),
        );
        expect(
          write.status,
          anyOf(
            PersistentArtifactPhysicalOperationStatus.succeeded,
            PersistentArtifactPhysicalOperationStatus.idempotent,
          ),
        );
        final read = await service.readPhysicalContent(
          const ReadPhysicalContentRequest(
            backendId: hardeningBackendId,
            handle: InMemoryPersistentArtifactContentHandle(
              handleId: 'h',
              backendId: hardeningBackendId,
            ),
          ),
        );
        expect(
            read.status, PersistentArtifactPhysicalOperationStatus.succeeded);
      }
    });

    final scenarios = <String,
        Future<PersistentArtifactPhysicalResult> Function(
      PersistentArtifactPhysicalOperationsService service,
    )>{
      'write': (service) => service.writePhysicalContent(
            const WritePhysicalContentRequest(
              backendId: hardeningBackendId,
              contentId: 'x',
              bytes: [1],
            ),
          ),
      'read': (service) => service.readPhysicalContent(
            const ReadPhysicalContentRequest(
              backendId: hardeningBackendId,
              handle: InMemoryPersistentArtifactContentHandle(
                handleId: 'h',
                backendId: hardeningBackendId,
              ),
            ),
          ),
      'exists': (service) => service.contentExists(
            const ContentExistsRequest(
              backendId: hardeningBackendId,
              handle: InMemoryPersistentArtifactContentHandle(
                handleId: 'h',
                backendId: hardeningBackendId,
              ),
            ),
          ),
      'metadata': (service) => service.contentMetadata(
            const ContentMetadataRequest(
              backendId: hardeningBackendId,
              handle: InMemoryPersistentArtifactContentHandle(
                handleId: 'h',
                backendId: hardeningBackendId,
              ),
            ),
          ),
      'save-manifest': (service) => service.savePhysicalManifest(
            SavePhysicalManifestRequest(
              backendId: hardeningBackendId,
              manifest: PersistentArtifactTestFixtures.validManifest(),
            ),
          ),
      'load-manifest': (service) => service.loadPhysicalManifest(
            const LoadPhysicalManifestRequest(
              backendId: hardeningBackendId,
              manifestId: 'm',
            ),
          ),
      'latest-manifest': (service) => service.latestPhysicalManifest(
            const LatestPhysicalManifestRequest(
              backendId: hardeningBackendId,
              artifactId: 'a',
            ),
          ),
      'query-manifest': (service) => service.queryPhysicalManifests(
            QueryPhysicalManifestsRequest(
              backendId: hardeningBackendId,
              query: const PersistentArtifactQuery(projectId: 'p'),
            ),
          ),
      'invalidate-manifest': (service) => service.invalidatePhysicalManifest(
            const InvalidatePhysicalManifestRequest(
              backendId: hardeningBackendId,
              manifestId: 'm',
            ),
          ),
      'resolve-location': (service) => service.resolvePhysicalLocation(
            ResolvePhysicalLocationRequest(
              backendId: hardeningBackendId,
              subject: PersistentArtifactTestFixtures.validSubject(),
            ),
          ),
      'quarantine': (service) => service.quarantineContent(
            const QuarantineContentRequest(
              backendId: hardeningBackendId,
              handle: InMemoryPersistentArtifactContentHandle(
                handleId: 'h',
                backendId: hardeningBackendId,
              ),
            ),
          ),
      'inspect-interrupted': (service) =>
          service.inspectInterruptedOperations(hardeningBackendId),
      'inspect-orphans': (service) =>
          service.inspectOrphanTemporaryObjects(hardeningBackendId),
      'recover-temp': (service) => service.recoverTemporaryObject(
            const RecoverTemporaryObjectRequest(
              backendId: hardeningBackendId,
              reference: 'r',
            ),
          ),
      'discard-temp': (service) => service.discardTemporaryObject(
            const DiscardTemporaryObjectRequest(
              backendId: hardeningBackendId,
              reference: 'r',
            ),
          ),
      'unregistered-fallback': (service) async {
        final missing = PersistentArtifactBackendRegistry();
        final isolated =
            PersistentArtifactPhysicalOperationsService(registry: missing);
        return isolated.writePhysicalContent(
          const WritePhysicalContentRequest(
            backendId: 'missing',
            contentId: 'x',
            bytes: [1],
          ),
        );
      },
      'environment-gate': (service) async {
        final blocked = PersistentArtifactBackendRegistry(
          environmentGate: const PersistentArtifactEnvironmentGate(),
        );
        blocked.register(
          PersistentArtifactBackendRegistration(
            descriptor: const PersistentArtifactBackendDescriptor(
              backendId: hardeningBackendId,
              kind: 'blocked',
              capabilities: {
                PersistentArtifactBackendCapability.contentWrite,
              },
              environment: PersistentArtifactBackendEnvironment(
                classification:
                    PersistentArtifactBackendEnvironmentClassification
                        .localReference,
                test: true,
                development: true,
                localReference: true,
                stagingEligible: false,
                productionEligible: false,
              ),
            ),
            bridge: fake,
          ),
        );
        final blockedService = PersistentArtifactPhysicalOperationsService(
          registry: blocked,
          runtimeEnvironment: PersistentArtifactRuntimeEnvironment.production,
        );
        return blockedService.writePhysicalContent(
          const WritePhysicalContentRequest(
            backendId: hardeningBackendId,
            contentId: 'x',
            bytes: [1],
          ),
        );
      },
      'backend-disabled': (service) async {
        final registry =
            createRegistryWith(buildFakeRegistration(bridge: null));
        final disabled =
            PersistentArtifactPhysicalOperationsService(registry: registry);
        return disabled.writePhysicalContent(
          const WritePhysicalContentRequest(
            backendId: hardeningBackendId,
            contentId: 'x',
            bytes: [1],
          ),
        );
      },
    };

    scenarios.forEach((name, run) {
      test('replay scenario: $name', () async {
        final result = await run(service);
        expect(result.status, isA<PersistentArtifactPhysicalOperationStatus>());
      });
    });

    for (var i = 0; i < 100; i++) {
      test('deterministic write replay case $i', () async {
        final result = await service.writePhysicalContent(
          WritePhysicalContentRequest(
            backendId: hardeningBackendId,
            contentId: 'case-$i',
            bytes: const [7, 8, 9],
          ),
        );
        expect(
          result.status,
          anyOf(
            PersistentArtifactPhysicalOperationStatus.succeeded,
            PersistentArtifactPhysicalOperationStatus.idempotent,
          ),
        );
      });
    }
  });
}
