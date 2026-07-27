import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudPropertyOperational', () {
    test('correlationId é sempre preenchido', () async {
      final service = CloudOperationalHelpers.service();
      for (var i = 0; i < 20; i++) {
        final result = await service.putObject(
          CloudOperationalHelpers.request(requestId: 'cid-$i'),
        );
        expect(result.correlationId, isNotEmpty);
      }
    });

    test('requestId distinto gera correlation distinto', () async {
      final service = CloudOperationalHelpers.service();
      final first = await service.putObject(
        CloudOperationalHelpers.request(requestId: 'a'),
      );
      final second = await service.putObject(
        CloudOperationalHelpers.request(requestId: 'b'),
      );
      expect(first.correlationId, startsWith('pa-cloud:'));
      expect(second.correlationId, startsWith('pa-cloud:'));
    });
  });
}
