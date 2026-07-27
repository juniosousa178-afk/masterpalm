import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/null_source_providers.dart';

void main() {
  test('composition e2e 22 step flow', () async {
    final composition = PersistentArtifactLocalReferenceComposition();
    final runtime = composition.create(
      filesystemConfig: const SecureFilesystemBackendConfig(
        backendId: 'comp-e2e',
        rootDirectory: 'C:/temp/masterpalm-hardening-e2e',
        maximumContentSizeBytes: 1024 * 1024,
      ),
      releaseEvidenceProvider: NullReleaseEvidenceProvider(),
      releaseSupplyChainProvider: NullReleaseSupplyChainProvider(),
      cicdIntegrationProvider: NullCicdProvider(),
      cryptographicTrustProvider: NullCryptographicTrustProvider(),
    );
    for (var i = 0; i < 22; i++) {
      final result = await runtime.provider.contentExists(
        const ContentExistsRequest(
          backendId: 'comp-e2e',
          handle: InMemoryPersistentArtifactContentHandle(
            handleId: 'h',
            backendId: 'comp-e2e',
          ),
        ),
      );
      expect(result.status, isA<PersistentArtifactPhysicalOperationStatus>());
    }
    runtime.dispose();
  });
}
