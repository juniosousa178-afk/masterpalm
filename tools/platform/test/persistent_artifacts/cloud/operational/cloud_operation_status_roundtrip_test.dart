import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  group('CloudOperationStatusRoundtrip', () {
    for (final status in PersistentArtifactCloudOperationStatus.values) {
      test('wire roundtrip ${status.name}', () {
        final wire = status.wireName;
        expect(
          PersistentArtifactCloudOperationStatusX.fromWireName(wire),
          status,
        );
      });
    }
  });
}
