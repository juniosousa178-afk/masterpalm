import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/cloud_operational_helpers.dart';

void main() {
  group('CloudPerformanceOperational', () {
    test('25 operações em janela aceitável', () async {
      final service = CloudOperationalHelpers.service();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 25; i++) {
        await service.putObject(
          CloudOperationalHelpers.request(
            requestId: 'perf-$i',
            objectKey: 'perf/object-$i.json',
          ),
        );
      }
      sw.stop();
      expect(sw.elapsedMilliseconds < 5000, isTrue);
    });
  });
}
