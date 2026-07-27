import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudOperationsService', () {
    test('put/get/head retornam success no fluxo feliz', () async {
      final service = CloudOperationalHelpers.service();
      final put = await service.putObject(CloudOperationalHelpers.request());
      final get = await service.getObject(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.getObject),
      );
      final head = await service.headObject(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.headObject),
      );
      expect(put.status, PersistentArtifactCloudOperationStatus.success);
      expect(get.status, PersistentArtifactCloudOperationStatus.success);
      expect(head.status, PersistentArtifactCloudOperationStatus.success);
    });

    test('objectExists retorna bool', () async {
      final service = CloudOperationalHelpers.service();
      final result = await service.objectExists(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.headObject),
      );
      expect(result.exists, isTrue);
    });

    test('listObjects retorna truncado quando bridge devolve 2 itens',
        () async {
      final service = CloudOperationalHelpers.service();
      final result = await service.listObjects(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.listObjects),
      );
      expect(result.truncated, isTrue);
      expect(result.objects.length, greaterThanOrEqualTo(1));
    });

    test('delete/copy/multipart mapeiam status', () async {
      final service = CloudOperationalHelpers.service();
      final del = await service.deleteObject(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.deleteObject),
      );
      final copy = await service.copyObject(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.copyObject),
      );
      final begin = await service.beginMultipart(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.beginMultipart),
      );
      final upload = await service.uploadPart(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.uploadPart),
      );
      final complete = await service.completeMultipart(
        CloudOperationalHelpers.request(
          operation: CloudOperationType.completeMultipart,
        ),
      );
      final abort = await service.abortMultipart(
        CloudOperationalHelpers.request(
            operation: CloudOperationType.abortMultipart),
      );

      expect(del.status,
          isNot(PersistentArtifactCloudOperationStatus.unavailable));
      expect(copy.status,
          isNot(PersistentArtifactCloudOperationStatus.unavailable));
      expect(begin.status,
          isNot(PersistentArtifactCloudOperationStatus.unavailable));
      expect(upload.status,
          isNot(PersistentArtifactCloudOperationStatus.unavailable));
      expect(complete.status,
          isNot(PersistentArtifactCloudOperationStatus.unavailable));
      expect(abort.status,
          isNot(PersistentArtifactCloudOperationStatus.unavailable));
    });

    test('sem bridge registrado retorna unavailable', () async {
      final service = PersistentArtifactCloudOperationsService(
        registry: PersistentArtifactBackendRegistry(),
      );
      final result = await service.putObject(
        CloudOperationalHelpers.request(backendId: 'missing'),
      );
      expect(
          result.status, PersistentArtifactCloudOperationStatus.unregistered);
    });

    test('gating bloqueia staging', () async {
      final service = CloudOperationalHelpers.service(
        runtimeEnvironment: PersistentArtifactRuntimeEnvironment.staging,
      );
      final result = await service.putObject(CloudOperationalHelpers.request());
      expect(
          result.status, PersistentArtifactCloudOperationStatus.stagingBlocked);
    });
  });
}
