import 'dart:convert';

import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../../../support/persistent_artifact_offline_cloud_reference_composition.dart';
import 'support/cloud_hardening_helpers.dart';

void main() {
  group('CloudHardeningReplay', () {
    late PersistentArtifactOfflineCloudReferenceRuntime runtime;

    setUp(() {
      runtime =
          const PersistentArtifactOfflineCloudReferenceComposition().create();
    });

    tearDown(() => runtime.dispose());

    test('100 ciclos cross-layer determinísticos', () async {
      for (var i = 0; i < 100; i++) {
        final request = CloudHardeningHelpers.putRequest(
          requestId: 'replay-$i',
          objectKey: 'releases/v1/replay-$i.json',
          backendId: runtime.backendId,
        );
        final encoded = jsonEncode(request.toJson());
        final decoded = PersistentArtifactCloudOperationRequest.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );
        expect(decoded.toComparableJson(), request.toComparableJson());

        final put = await runtime.service.putObject(decoded);
        final head = await runtime.service.headObject(
          decoded.copyWith(operationType: CloudOperationType.headObject),
        );
        final providerPut = await runtime.provider.putCloudObject(decoded);

        expect(put.status, PersistentArtifactCloudOperationStatus.success);
        expect(head.status, PersistentArtifactCloudOperationStatus.success);
        expect(providerPut.status, put.status);
        expect(put.status.wireName, 'success');
        expect(put.correlationId, isNotEmpty);
        expect(put.metadata.containsKey('credential'), isFalse);
      }
    });
  });
}
