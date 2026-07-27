import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import '../support/cloud_test_fixtures.dart';
import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudMalformedOperational', () {
    test('backend ausente retorna unregistered', () async {
      final service = CloudOperationalHelpers.service(
        registry: PersistentArtifactBackendRegistry(),
      );
      final result = await service.getObject(
        CloudOperationalHelpers.request(
          backendId: 'missing',
          operation: CloudOperationType.getObject,
        ),
      );
      expect(
          result.status, PersistentArtifactCloudOperationStatus.unregistered);
    });

    test('request com objectReference null não quebra serviço', () async {
      final service = CloudOperationalHelpers.service();
      final malformed = CloudTestFixtures.operationRequest().copyWith(
        operationType: CloudOperationType.headObject,
        objectReference: null,
      );
      final result = await service.headObject(malformed);
      expect(
        {
          PersistentArtifactCloudOperationStatus.failed,
          PersistentArtifactCloudOperationStatus.notFound,
          PersistentArtifactCloudOperationStatus.success,
        }.contains(result.status),
        isTrue,
      );
    });
  });
}
