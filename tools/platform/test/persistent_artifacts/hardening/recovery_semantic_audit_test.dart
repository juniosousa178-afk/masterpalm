import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('recovery result carries references', () {
    const result = RecoveryInspectionResult(
      status: PersistentArtifactPhysicalOperationStatus.succeeded,
      references: [RecoveryObjectReference(referenceId: 'tmp-1')],
    );
    expect(result.references.single.referenceId, 'tmp-1');
  });
}
