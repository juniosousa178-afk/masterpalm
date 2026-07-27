import 'package:masterpalm_platform/masterpalm_platform_filesystem.dart';
import 'package:test/test.dart';

void main() {
  test('filesystem bridge type exported in filesystem entrypoint', () {
    SecureFilesystemPhysicalBackendBridge? bridge;
    expect(bridge, isNull);
  });
}
