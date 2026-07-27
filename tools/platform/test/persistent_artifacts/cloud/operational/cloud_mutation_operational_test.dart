import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudMutationOperational', () {
    test('put seguido de get preserva objectKey', () async {
      final service = CloudOperationalHelpers.service();
      for (var i = 0; i < 15; i++) {
        final key = 'releases/v2/object-$i.json';
        await service
            .putObject(CloudOperationalHelpers.request(objectKey: key));
        final result = await service.getObject(
          CloudOperationalHelpers.request(
            operation: CloudOperationType.getObject,
            objectKey: key,
          ),
        );
        expect(result.objectReference?.objectKey, key);
      }
    });
  });
}
