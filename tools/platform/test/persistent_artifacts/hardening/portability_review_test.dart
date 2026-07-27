import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('vendor-neutral bridge is available from core export', () {
    PersistentArtifactPhysicalBackendBridge? bridge;
    expect(bridge, isNull);
  });
}
