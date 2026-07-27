import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

void main() {
  test('filesystem entrypoint exports composition factory', () {
    final composition = createPersistentArtifactLocalReferenceComposition();
    expect(composition, isNotNull);
  });
}
