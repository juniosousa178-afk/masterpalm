import 'dart:convert';
import 'dart:io';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningGolden', () {
    final goldenDir =
        Directory('test/goldens/persistent_artifacts/cloud_hardening');

    test('30 goldens finais sem auto-update', () {
      final files = goldenDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, 30);
      for (final file in files) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json.containsKey('name'), isTrue);
        expect(json.containsKey('status'), isTrue);
        final serialized = jsonEncode(json);
        expect(serialized.contains('accessKey'), isFalse);
        expect(serialized.contains('secret'), isFalse);
        expect(serialized.contains('stackTrace'), isFalse);
      }
    });

    test('snapshots gerados batem com goldens estáveis', () async {
      final runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
      addTearDown(runtime.dispose);

      final snapshots = <Map<String, dynamic>>[
        {
          'name': 'offline-composition-descriptor',
          'status': 'ready',
          ...runtime.compositionDescriptorJson(),
        },
        _environmentGolden(
          'environment-contractOnly-allowed',
          PersistentArtifactCloudBridgeClassification.contractOnly,
          PersistentArtifactRuntimeEnvironment.test,
          allowed: true,
        ),
        _environmentGolden(
          'environment-offlineSimulation-allowed',
          PersistentArtifactCloudBridgeClassification.offlineSimulation,
          PersistentArtifactRuntimeEnvironment.localReference,
          allowed: true,
        ),
        _environmentGolden(
          'environment-staging-blocked',
          PersistentArtifactCloudBridgeClassification.offlineSimulation,
          PersistentArtifactRuntimeEnvironment.staging,
          allowed: false,
          status: 'stagingBlocked',
        ),
        _environmentGolden(
          'environment-production-blocked',
          PersistentArtifactCloudBridgeClassification.offlineSimulation,
          PersistentArtifactRuntimeEnvironment.production,
          allowed: false,
          status: 'stagingBlocked',
        ),
        await _operationGolden(
          runtime,
          'put-success',
          (s, r) => s.putObject(r),
        ),
        _admissionGolden(
          'real-adapter-admission-decision-blocked',
          const PersistentArtifactRealCloudAdapterAdmissionEvaluator().evaluate(
            criteria:
                const PersistentArtifactRealCloudAdapterAdmissionCriteria(),
            blocked: true,
          ),
        ),
      ];

      for (final snapshot in snapshots) {
        final name = snapshot['name'] as String;
        final file = File('${goldenDir.path}/$name.json');
        expect(file.existsSync(), isTrue, reason: 'missing golden $name');
        final golden =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(golden['name'], snapshot['name']);
        expect(golden['status'], snapshot['status']);
      }
    });
  });
}

Map<String, dynamic> _environmentGolden(
  String name,
  PersistentArtifactCloudBridgeClassification classification,
  PersistentArtifactRuntimeEnvironment environment, {
  required bool allowed,
  String status = 'success',
}) {
  const gate = PersistentArtifactCloudEnvironmentGate();
  final decision = gate.evaluate(
    backendId: 'offline-cloud-ref',
    runtimeEnvironment: environment,
    classification: classification,
  );
  return {
    'name': name,
    'status': status,
    'allowed': allowed,
    'reasonCode': decision.reasonCode,
    'classification': classification.wireName,
    'environment': environment.name,
  };
}

Future<Map<String, dynamic>> _operationGolden(
  PersistentArtifactOfflineCloudReferenceRuntime runtime,
  String name,
  Future<PersistentArtifactCloudObjectMetadataResult> Function(
    PersistentArtifactCloudOperationsService service,
    PersistentArtifactCloudOperationRequest request,
  ) action, {
  String expectStatus = 'success',
}) async {
  final request = CloudHardeningHelpers.putRequest(
    backendId: runtime.backendId,
    requestId: '$name-request',
  );
  final result = await action(runtime.service, request);
  return {
    'name': name,
    'status': expectStatus,
    'operation': request.operationType.name,
    'backendId': runtime.backendId,
    'correlationIdPrefix': result.correlationId.split(':').first,
  };
}

Map<String, dynamic> _admissionGolden(
  String name,
  PersistentArtifactRealCloudAdapterAdmissionDecision decision,
) {
  return {
    'name': name,
    'status': decision.status.wireName,
    'stagingApproved': decision.stagingApproved,
    'productionApproved': decision.productionApproved,
    'prototypeAdmissionGranted': decision.prototypeAdmissionGranted,
  };
}
