import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('correlation request does not expose content bytes', () {
    final correlation = PersistentArtifactPhysicalCorrelation.fromRequest(
      operation: 'writeContent',
      backendId: 'opaque-backend',
    );
    expect(correlation.correlationId.contains('[1,2,3]'), isFalse);
  });
}
