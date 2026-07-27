import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudRegistryIntegration', () {
    test('cloudRegistrationOf retorna handle', () {
      final registry = CloudOperationalHelpers.registryWithBridge();
      final handle = registry.cloudRegistrationOf('cloud-backend-1');
      expect(handle, isNotNull);
      expect(handle!.backendId, 'cloud-backend-1');
    });

    test('resolveCloudBackend sem registro retorna unregistered', () {
      final registry = PersistentArtifactBackendRegistry();
      final resolution = registry.resolveCloudBackend('missing');
      expect(resolution.resolved, isFalse);
      expect(resolution.status,
          PersistentArtifactCloudOperationStatus.unregistered);
    });

    test('resolveCloudBackendForOperation em backend registrado resolve', () {
      final registry = CloudOperationalHelpers.registryWithBridge();
      final resolution = registry.resolveCloudBackendForOperation(
        'cloud-backend-1',
        PersistentArtifactCloudCapability.abortMultipart,
      );
      expect(resolution.resolved, isTrue);
      expect(resolution.status, PersistentArtifactCloudOperationStatus.success);
    });

    test('queryCloudCapabilities expõe mapa determinístico', () {
      final registry = CloudOperationalHelpers.registryWithBridge();
      final capabilities = registry.queryCloudCapabilities();
      expect(capabilities.keys.toList(), ['cloud-backend-1']);
      expect(
        capabilities['cloud-backend-1'],
        contains(PersistentArtifactCloudCapability.putObject),
      );
    });

    test('evaluateCloudEnvironment bloqueia production', () {
      final registry = CloudOperationalHelpers.registryWithBridge();
      final decision = registry.evaluateCloudEnvironment(
        'cloud-backend-1',
        PersistentArtifactRuntimeEnvironment.production,
      );
      expect(decision.allowed, isFalse);
      expect(decision.status,
          PersistentArtifactCloudOperationStatus.stagingBlocked);
    });
  });
}
