import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('malformed status input falls back to failed', () {
    final status =
        PersistentArtifactPhysicalOperationJsonCodec.statusFromJson('unknown');
    expect(status, PersistentArtifactPhysicalOperationStatus.failed);
  });
}
