import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('quarantined status stays explicit', () {
    const result = QuarantineContentResult(
      status: PersistentArtifactPhysicalOperationStatus.quarantined,
      quarantined: true,
    );
    expect(result.quarantined, isTrue);
  });
}
