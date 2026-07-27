import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudReplay', () {
    test('100 ciclos determinísticos sem regressão de status', () async {
      final service = CloudOperationalHelpers.service();
      for (var i = 0; i < 100; i++) {
        final request = CloudOperationalHelpers.request(
          requestId: 'replay-$i',
          objectKey: 'releases/v1/replay-$i.json',
          operation: CloudOperationType.putObject,
        );
        final put = await service.putObject(request);
        final head = await service.headObject(
          request.copyWith(operationType: CloudOperationType.headObject),
        );
        expect(put.status, PersistentArtifactCloudOperationStatus.success);
        expect(head.status, PersistentArtifactCloudOperationStatus.success);
      }
    });
  });
}
