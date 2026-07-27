import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudProviderIntegration', () {
    test('PlatformPersistentArtifactProvider delega para cloud service',
        () async {
      final provider = PlatformPersistentArtifactProvider(
        policyRegistry: PersistentArtifactPolicyRegistry(),
        sourceResolver: PersistentArtifactSourceResolver(
          releaseEvidenceProvider: _NoopReleaseEvidenceProvider(),
          releaseSupplyChainProvider: _NoopReleaseSupplyChainProvider(),
          cicdIntegrationProvider: _NoopCicdProvider(),
          cryptographicTrustProvider: _NoopCryptoProvider(),
        ),
        store: InMemoryPersistentArtifactSnapshotStore(),
        backendRegistry: CloudOperationalHelpers.registryWithBridge(),
      );
      final result = await provider.putCloudObject(
        CloudOperationalHelpers.request(),
      );
      expect(result.status, PersistentArtifactCloudOperationStatus.success);
    });

    test('Sem registry cloud retorna unavailable', () async {
      final provider = PlatformPersistentArtifactProvider(
        policyRegistry: PersistentArtifactPolicyRegistry(),
        sourceResolver: PersistentArtifactSourceResolver(
          releaseEvidenceProvider: _NoopReleaseEvidenceProvider(),
          releaseSupplyChainProvider: _NoopReleaseSupplyChainProvider(),
          cicdIntegrationProvider: _NoopCicdProvider(),
          cryptographicTrustProvider: _NoopCryptoProvider(),
        ),
        store: InMemoryPersistentArtifactSnapshotStore(),
      );
      final result = await provider.putCloudObject(
        CloudOperationalHelpers.request(),
      );
      expect(result.status, PersistentArtifactCloudOperationStatus.unavailable);
    });
  });
}

class _NoopReleaseEvidenceProvider implements ReleaseEvidenceProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopReleaseSupplyChainProvider implements ReleaseSupplyChainProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopCicdProvider implements CicdIntegrationProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoopCryptoProvider implements CryptographicTrustProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
