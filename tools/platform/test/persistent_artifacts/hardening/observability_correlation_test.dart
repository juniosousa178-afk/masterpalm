import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('correlation id is generated for write', () {
    final correlation = PersistentArtifactPhysicalCorrelation.forWrite(
      const WritePhysicalContentRequest(
        backendId: 'b',
        contentId: 'c',
        bytes: [1],
      ),
    );
    expect(correlation.correlationId, contains('writeContent'));
    expect(correlation.backendId, 'b');
  });
}
