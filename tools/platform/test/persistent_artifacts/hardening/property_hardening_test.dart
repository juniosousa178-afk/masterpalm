import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('operation status enum keeps hardening members', () {
    expect(
      PersistentArtifactPhysicalOperationStatus.values.contains(
          PersistentArtifactPhysicalOperationStatus.environmentBlocked),
      isTrue,
    );
    expect(
      PersistentArtifactPhysicalOperationStatus.values
          .contains(PersistentArtifactPhysicalOperationStatus.backendDisabled),
      isTrue,
    );
  });
}
