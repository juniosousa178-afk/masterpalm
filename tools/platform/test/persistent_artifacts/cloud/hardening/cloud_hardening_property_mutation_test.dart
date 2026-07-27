import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import '../operational/support/cloud_operational_helpers.dart';
import '../support/fake_persistent_artifact_cloud_backend_bridge.dart';
import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningProperty', () {
    test('backendId explícito em 50 operações com seed fixa', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      for (var i = 0; i < 50; i++) {
        final result = await runtime.service.putObject(
          CloudHardeningHelpers.putRequest(
            backendId: runtime.backendId,
            requestId: 'seed-$i',
            objectKey: 'releases/seed/$i.json',
          ),
        );
        expect(result.backendId, runtime.backendId);
      }
    });

    test('staging e production permanecem bloqueados', () {
      const gate = PersistentArtifactCloudEnvironmentGate();
      for (final env in [
        PersistentArtifactRuntimeEnvironment.staging,
        PersistentArtifactRuntimeEnvironment.production,
      ]) {
        final decision = gate.evaluate(
          backendId: 'b1',
          runtimeEnvironment: env,
          classification:
              PersistentArtifactCloudBridgeClassification.offlineSimulation,
        );
        expect(decision.allowed, isFalse);
      }
    });
  });

  group('CloudHardeningMutation', () {
    test('fake bridge não está em lib', () {
      expect(
        Directory('lib').listSync(recursive: true).whereType<File>().any(
              (f) => f.path.contains('fake_persistent_artifact_cloud'),
            ),
        isFalse,
      );
    });

    test('sucesso cloud não autoriza release', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);
      final put = await runtime.service.putObject(
        CloudOperationalHelpers.request(backendId: runtime.backendId),
      );
      expect(put.status, PersistentArtifactCloudOperationStatus.success);
      final admission =
          const PersistentArtifactRealCloudAdapterAdmissionEvaluator().evaluate(
              criteria:
                  const PersistentArtifactRealCloudAdapterAdmissionCriteria());
      expect(admission.prototypeAdmissionGranted, isFalse);
    });
  });

  group('CloudHardeningMalformed', () {
    test('backendId vazio retorna invalid sem bridge call', () async {
      final bridge = FakePersistentArtifactCloudBackendBridge();
      final runtime = const PersistentArtifactOfflineCloudReferenceComposition()
          .create(bridge: bridge);
      addTearDown(runtime.dispose);
      final result = await runtime.service.putObject(
        CloudHardeningHelpers.putRequest(backendId: ''),
      );
      expect(
        result.status,
        anyOf(
          PersistentArtifactCloudOperationStatus.invalid,
          PersistentArtifactCloudOperationStatus.unregistered,
          PersistentArtifactCloudOperationStatus.unavailable,
        ),
      );
      expect(bridge.operationCounters.isEmpty, isTrue);
    });
  });
}
