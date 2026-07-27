import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

import 'support/null_source_providers.dart';

void main() {
  group('composition root lifecycle', () {
    test('create/register/use/unregister/dispose', () async {
      final composition = PersistentArtifactLocalReferenceComposition();
      final runtime = composition.create(
        filesystemConfig: const SecureFilesystemBackendConfig(
          backendId: 'comp-root',
          rootDirectory: 'C:/temp/masterpalm-hardening',
          maximumContentSizeBytes: 1024 * 1024,
        ),
        releaseEvidenceProvider: NullReleaseEvidenceProvider(),
        releaseSupplyChainProvider: NullReleaseSupplyChainProvider(),
        cicdIntegrationProvider: NullCicdProvider(),
        cryptographicTrustProvider: NullCryptographicTrustProvider(),
      );
      expect(runtime.registry.contains('comp-root'), isTrue);
      final write = await runtime.provider.writePhysicalContent(
        const WritePhysicalContentRequest(
          backendId: 'comp-root',
          contentId: 'x',
          bytes: [1, 2, 3],
        ),
      );
      expect(write.status, isA<PersistentArtifactPhysicalOperationStatus>());
      runtime.unregister();
      expect(runtime.registry.contains('comp-root'), isFalse);
      runtime.dispose();
      runtime.dispose();
      expect(runtime.isDisposed, isTrue);
    });
  });
}
