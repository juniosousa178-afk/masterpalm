import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

void main() {
  test('write request json is mutable-safe by reconstruction', () {
    const request = WritePhysicalContentRequest(
      backendId: 'b',
      contentId: 'c',
      bytes: [1, 2, 3],
    );
    final json = request.toJson();
    final restored =
        PersistentArtifactPhysicalOperationJsonCodec.writeRequestFromJson(json);
    expect(restored.contentId, request.contentId);
    expect(restored.bytes, request.bytes);
  });
}
