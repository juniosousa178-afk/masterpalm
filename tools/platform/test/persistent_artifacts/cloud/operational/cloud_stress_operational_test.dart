import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudStressOperational', () {
    test('50 operações sequenciais sem erro', () async {
      final service = CloudOperationalHelpers.service();
      for (var i = 0; i < 50; i++) {
        final key = 'stress/object-$i.json';
        final result = await service.putObject(
          CloudOperationalHelpers.request(
            requestId: 'stress-$i',
            objectKey: key,
          ),
        );
        expect(result.status, PersistentArtifactCloudOperationStatus.success);
      }
    });
  });
}
