import 'package:masterpalm_platform/masterpalm_platform.dart';
import 'package:test/test.dart';

import 'support/persistent_artifact_hardening_helpers.dart';

void main() {
  group('Persistent Artifact provider audit', () {
    late PersistentArtifactTestStack stack;

    setUp(() {
      stack = createTestStack();
    });

    test('evaluate does not persist snapshot', () async {
      final result = await stack.provider.evaluate(passingScenarioRequest());
      expect(result.snapshot, isNotNull);
      expect(await stack.store.count(), 0);
    });

    test('evaluateAndPublish persists snapshot and can be loaded', () async {
      final result =
          await stack.provider.evaluateAndPublish(passingScenarioRequest());
      final loaded =
          await stack.provider.load(result.snapshotReference!.snapshotId);
      expect(loaded, isNotNull);
      expect(await stack.store.count(), 1);
    });

    test('invalidate non-existing snapshot throws not found', () async {
      expect(
        () => stack.provider.invalidate('missing-id'),
        throwsA(isA<PersistentArtifactNotFoundException>()),
      );
    });

    test('content operations fail without physical backend', () async {
      expect(
        () => stack.provider.writeContent(contentId: 'c', bytes: const [1]),
        throwsA(isA<PersistentArtifactContentUnavailableException>()),
      );
      expect(
        () => stack.provider.readContent(
          const InMemoryPersistentArtifactContentHandle(
              handleId: 'h', backendId: 'b'),
        ),
        throwsA(isA<PersistentArtifactContentUnavailableException>()),
      );
    });
  });
}
